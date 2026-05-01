import Foundation
import SwiftData

/// Background metadata passes: periodically fills missing covers from local folders and ScreenScraper when credentials are set.
@MainActor
final class MetadataBackgroundFetcher {
    static let shared = MetadataBackgroundFetcher()
    struct ScrapeSummary: Sendable {
        var processed: Int
        var updated: Int
    }

    private var loopTask: Task<Void, Never>?
    private var container: ModelContainer?

    private init() {}
    private static let localCoverExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "tif", "tiff", "avif"
    ]
    private static let likelyCoverFolderNames: Set<String> = [
        "cover", "covers", "boxart", "art", "images", "image", "posters", "media"
    ]

    func startIfNeeded(container: ModelContainer) {
        self.container = container
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Run one batch soon (e.g. after a scan adds new games).
    func scheduleExtraPass(container: ModelContainer) {
        Task { @MainActor in
            self.container = container
            _ = await processBatch(container: container, forceAll: false, maxGames: 3)
        }
    }

    /// Trigger a user-requested scrape pass across the full library.
    func scrapeAllNow(container: ModelContainer) async -> ScrapeSummary {
        self.container = container
        return await processBatch(container: container, forceAll: true, maxGames: nil)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            if let c = container {
                _ = await processBatch(container: c, forceAll: false, maxGames: 3)
            }
            try? await Task.sleep(for: .seconds(45))
        }
    }

    private func processBatch(container: ModelContainer, forceAll: Bool, maxGames: Int?) async -> ScrapeSummary {
        let context = container.mainContext
        var descriptor = FetchDescriptor<LibraryGame>(sortBy: [SortDescriptor(\.sortOrder)])
        descriptor.fetchLimit = forceAll ? 0 : 250

        let games = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        let retryInterval: TimeInterval = 24 * 3600

        let candidates = games.filter { g in
            if forceAll { return true }
            if let t = g.metadataLastFetchAt {
                return now.timeIntervalSince(t) > retryInterval
            }
            return true
        }

        let selectedCandidates: [LibraryGame]
        if let maxGames {
            selectedCandidates = Array(candidates.prefix(maxGames))
        } else {
            selectedCandidates = candidates
        }

        var processed = 0
        var updated = 0
        for game in selectedCandidates {
            if Task.isCancelled { break }
            processed += 1
            if await fetchAndSave(gameID: game.id, container: container) {
                updated += 1
            }
            try? await Task.sleep(for: .milliseconds(450))
        }
        return ScrapeSummary(processed: processed, updated: updated)
    }

    private func fetchAndSave(gameID: UUID, container: ModelContainer) async -> Bool {
        let context = container.mainContext
        var desc = FetchDescriptor<LibraryGame>(predicate: #Predicate { $0.id == gameID })
        desc.fetchLimit = 1
        guard let game = try? context.fetch(desc).first else { return false }

        let romStem = URL(fileURLWithPath: game.romPath).deletingPathExtension().lastPathComponent
        let searchTitle = game.libraryListTitle
        let preferScreenScraper = game.emulator?.preferScreenScraperCovers == true
        let localCoverURL = localCoverForGame(path: game.romPath, title: searchTitle, romStem: romStem)
        var remoteResult: MetadataResult?
        if MetadataCredentials.isConfigured {
            remoteResult = try? await MetadataService.fetchMetadata(
                displayTitle: searchTitle,
                romFileNameStem: romStem,
                platformHint: game.platformHint
            )
        }

        var didChange = false

        if let normalized = remoteResult?.normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
           !normalized.isEmpty,
           game.title != normalized {
            game.title = normalized
            didChange = true
        }

        var options = game.coverImageOptions
        if let localCoverURL {
            let localCandidate = localCoverURL.absoluteString
            if !options.contains(localCandidate) {
                options.insert(localCandidate, at: 0)
                didChange = true
            }
        }
        if let remoteURL = remoteResult?.coverImageURL {
            let remoteCandidate = remoteURL.absoluteString
            if !options.contains(remoteCandidate) {
                options.append(remoteCandidate)
                didChange = true
            }
        }

        let priorPrimary = game.coverImageURLString
        game.coverImageOptions = options

        let preferredPrimary: String? = {
            if preferScreenScraper {
                if let remote = remoteResult?.coverImageURL?.absoluteString { return remote }
                if let local = localCoverURL?.absoluteString { return local }
            } else {
                if let local = localCoverURL?.absoluteString { return local }
                if let remote = remoteResult?.coverImageURL?.absoluteString { return remote }
            }
            return game.coverImageURLString
        }()

        if let preferredPrimary, preferredPrimary != game.coverImageURLString {
            game.coverImageURLString = preferredPrimary
            didChange = true
        }

        game.metadataLastFetchAt = Date()
        if priorPrimary != game.coverImageURLString {
            didChange = true
        }
        if didChange {
            try? context.save()
        } else {
            try? context.save()
        }
        return didChange
    }

    private func localCoverForGame(path: String, title: String, romStem: String) -> URL? {
        let gameURL = URL(fileURLWithPath: (path as NSString).standardizingPath)
        let gameDir = gameURL.hasDirectoryPath ? gameURL : gameURL.deletingLastPathComponent()
        let candidateDirectories = coverSearchDirectories(startingAt: gameDir)
        let targetTokens = searchableTokens(from: title + " " + romStem)
        let fallbackStem = romStem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !targetTokens.isEmpty || !fallbackStem.isEmpty else { return nil }

        let fm = FileManager.default
        var best: (score: Int, url: URL)?
        for directory in candidateDirectories {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in items {
                let ext = item.pathExtension.lowercased()
                guard Self.localCoverExtensions.contains(ext) else { continue }
                let stem = item.deletingPathExtension().lastPathComponent
                let stemTokens = searchableTokens(from: stem)
                var score = 0
                if !targetTokens.isEmpty {
                    let overlap = targetTokens.intersection(stemTokens).count
                    score += overlap * 10
                }
                if !fallbackStem.isEmpty, stem.lowercased().contains(fallbackStem) {
                    score += 8
                }
                if score <= 0 { continue }

                if let best, best.score >= score { continue }
                best = (score, item)
            }
        }
        return best?.url
    }

    private func coverSearchDirectories(startingAt gameDirectory: URL) -> [URL] {
        var directories: [URL] = []
        var current = gameDirectory
        let fm = FileManager.default

        for _ in 0..<3 {
            directories.append(current)
            if let children = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for child in children {
                    let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard isDirectory else { continue }
                    let name = child.lastPathComponent.lowercased()
                    if Self.likelyCoverFolderNames.contains(name) {
                        directories.append(child)
                    }
                }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return directories
    }

    private func searchableTokens(from raw: String) -> Set<String> {
        let cleaned = raw.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return Set(
            String(cleaned)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }
}
