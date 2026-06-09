import Foundation

struct MetadataResult: Sendable {
    var normalizedTitle: String
    var coverImageURL: URL?
    var screenScraperGameId: Int?
    var screenScraperSystemId: Int?
    /// True when the match was chosen algorithmically from an otherwise ambiguous result set.
    var autoResolvedAmbiguity: Bool = false
}

struct ScreenScraperDisambiguationRequest: Sendable, Identifiable, Hashable {
    let id: UUID
    let libraryGameId: UUID
    let libraryTitle: String
    let searchQuery: String
    let candidates: [ScreenScraperGameMatch]

    init(libraryGameId: UUID, libraryTitle: String, searchQuery: String, candidates: [ScreenScraperGameMatch]) {
        self.id = libraryGameId
        self.libraryGameId = libraryGameId
        self.libraryTitle = libraryTitle
        self.searchQuery = searchQuery
        self.candidates = candidates
    }
}

enum MetadataFetchOutcome: Sendable {
    case resolved(MetadataResult)
    case needsDisambiguation(ScreenScraperDisambiguationRequest)
    case unavailable
}

/// Fetches game metadata and cover art.
enum MetadataService {
    /// Returns normalized title and optional cover URL, or `nil` if credentials are not configured.
    static func fetchMetadata(
        libraryGameId: UUID,
        displayTitle: String,
        romFileNameStem: String,
        emulatorSystemId: Int?,
        pinnedGameId: Int?,
        pinnedSystemId: Int?,
        selectionSkipped: Bool = false
    ) async throws -> MetadataFetchOutcome? {
        guard MetadataCredentials.isConfigured else { return nil }
        if selectionSkipped { return .unavailable }

        let query = searchQuery(displayTitle: displayTitle, romFileNameStem: romFileNameStem)

        if let pinnedGameId, let pinnedSystemId {
            let match = try await ScreenScraperClient.fetchGame(
                gameId: pinnedGameId,
                systemId: pinnedSystemId,
                fallbackTitle: displayTitle
            )
            return .resolved(metadataResult(from: match))
        }

        var candidates: [ScreenScraperGameMatch] = []
        if let emulatorSystemId {
            candidates = (try? await ScreenScraperClient.searchGames(searchQuery: query, systemId: emulatorSystemId)) ?? []
        }
        if candidates.isEmpty {
            candidates = (try? await ScreenScraperClient.searchGames(searchQuery: query, systemId: nil)) ?? []
        }

        guard !candidates.isEmpty else { return .unavailable }

        let deduped = deduplicatedCandidates(candidates)
        if let auto = autoSelectedMatch(from: deduped, emulatorSystemId: emulatorSystemId, searchQuery: query) {
            let enriched = try await ScreenScraperClient.fetchGame(
                gameId: auto.gameId,
                systemId: auto.systemId,
                fallbackTitle: auto.title
            )
            return .resolved(metadataResult(from: enriched))
        }

        let promptCandidates: [ScreenScraperGameMatch]
        if let emulatorSystemId {
            let onEmulator = deduped.filter { $0.systemId == emulatorSystemId }
            promptCandidates = onEmulator.isEmpty ? deduped : onEmulator
        } else {
            promptCandidates = deduped
        }

        if MetadataCredentials.screenScraperAutoSelectAmbiguousMatches,
           let pick = algorithmicPick(from: promptCandidates, emulatorSystemId: emulatorSystemId, searchQuery: query) {
            let enriched = try await ScreenScraperClient.fetchGame(
                gameId: pick.gameId,
                systemId: pick.systemId,
                fallbackTitle: pick.title
            )
            var result = metadataResult(from: enriched)
            result.autoResolvedAmbiguity = true
            return .resolved(result)
        }

        let prompt = ScreenScraperDisambiguationRequest(
            libraryGameId: libraryGameId,
            libraryTitle: displayTitle,
            searchQuery: query,
            candidates: promptCandidates
        )
        return .needsDisambiguation(prompt)
    }

    static func searchQuery(displayTitle: String, romFileNameStem: String) -> String {
        let fromRom = RomTitleNormalizer.searchQuery(fromFileNameStem: romFileNameStem)
        let fromDisplay = RomTitleNormalizer.searchQuery(fromFileNameStem: displayTitle)
        return [fromRom, fromDisplay].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? displayTitle
    }

    private static func metadataResult(from match: ScreenScraperGameMatch) -> MetadataResult {
        MetadataResult(
            normalizedTitle: match.title,
            coverImageURL: match.coverURL,
            screenScraperGameId: match.gameId,
            screenScraperSystemId: match.systemId
        )
    }

    private static func deduplicatedCandidates(_ candidates: [ScreenScraperGameMatch]) -> [ScreenScraperGameMatch] {
        var seen = Set<String>()
        var output: [ScreenScraperGameMatch] = []
        for candidate in candidates {
            let key = "\(candidate.gameId)-\(candidate.systemId)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(candidate)
        }
        return output
    }

    private static func autoSelectedMatch(
        from candidates: [ScreenScraperGameMatch],
        emulatorSystemId: Int?,
        searchQuery: String
    ) -> ScreenScraperGameMatch? {
        if candidates.count == 1 {
            return candidates[0]
        }

        if let emulatorSystemId {
            let emulatorMatches = candidates.filter { $0.systemId == emulatorSystemId }
            if emulatorMatches.count == 1 {
                return emulatorMatches[0]
            }
            if let best = bestTitleMatch(searchQuery: searchQuery, in: emulatorMatches) {
                return best
            }
        }

        let distinctSystems = Set(candidates.map(\.systemId))
        if distinctSystems.count == 1 {
            if let best = bestTitleMatch(searchQuery: searchQuery, in: candidates) {
                return best
            }
            return candidates[0]
        }

        if let best = bestTitleMatch(searchQuery: searchQuery, in: candidates) {
            return best
        }

        return nil
    }

    private static func bestTitleMatch(searchQuery: String, in candidates: [ScreenScraperGameMatch]) -> ScreenScraperGameMatch? {
        let query = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !candidates.isEmpty else { return nil }

        let queryTokens = Set(
            query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
        )

        let scored = candidates.map { candidate -> (ScreenScraperGameMatch, Int) in
            let title = candidate.title.lowercased()
            var score = 0
            if title == query { score += 200 }
            if title.hasPrefix(query) || query.hasPrefix(title) { score += 120 }
            if title.contains(query) { score += 80 }
            if query.contains(title) && !title.isEmpty { score += 60 }

            let titleTokens = Set(
                title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
            )
            score += queryTokens.intersection(titleTokens).count * 15
            return (candidate, score)
        }.sorted { $0.1 > $1.1 }

        guard let top = scored.first, top.1 > 0 else { return nil }
        if scored.count == 1 { return top.0 }
        if scored.count > 1, top.1 > scored[1].1 {
            return top.0
        }
        return nil
    }

    /// Best-effort pick when the user allows automatic resolution of ambiguous matches.
    private static func algorithmicPick(
        from candidates: [ScreenScraperGameMatch],
        emulatorSystemId: Int?,
        searchQuery: String
    ) -> ScreenScraperGameMatch? {
        guard !candidates.isEmpty else { return nil }

        let pool: [ScreenScraperGameMatch]
        if let emulatorSystemId {
            let onEmulator = candidates.filter { $0.systemId == emulatorSystemId }
            pool = onEmulator.isEmpty ? candidates : onEmulator
        } else {
            pool = candidates
        }

        if pool.count == 1 {
            return pool[0]
        }

        if let best = bestTitleMatchRelaxed(searchQuery: searchQuery, in: pool) {
            return best
        }

        return pool[0]
    }

    /// Like [bestTitleMatch] but always returns the top-scoring candidate (ScreenScraper relevance order breaks ties).
    private static func bestTitleMatchRelaxed(searchQuery: String, in candidates: [ScreenScraperGameMatch]) -> ScreenScraperGameMatch? {
        let query = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates.first }

        let queryTokens = Set(
            query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
        )

        let scored = candidates.map { candidate -> (ScreenScraperGameMatch, Int) in
            let title = candidate.title.lowercased()
            var score = 0
            if title == query { score += 200 }
            if title.hasPrefix(query) || query.hasPrefix(title) { score += 120 }
            if title.contains(query) { score += 80 }
            if query.contains(title) && !title.isEmpty { score += 60 }

            let titleTokens = Set(
                title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
            )
            score += queryTokens.intersection(titleTokens).count * 15
            return (candidate, score)
        }.sorted { $0.1 > $1.1 }

        return scored.first?.0
    }
}
