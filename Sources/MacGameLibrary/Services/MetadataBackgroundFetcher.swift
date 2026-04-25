import Foundation
import SwiftData

/// Background metadata passes (similar in role to Playnite’s `MetadataDownloader` / library update jobs): periodically fills missing covers via IGDB when credentials are set.
@MainActor
final class MetadataBackgroundFetcher {
    static let shared = MetadataBackgroundFetcher()

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
            await processBatch(container: container)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            if let c = container {
                await processBatch(container: c)
            }
            try? await Task.sleep(for: .seconds(45))
        }
    }

    private func processBatch(container: ModelContainer) async {
        let context = container.mainContext
        var descriptor = FetchDescriptor<LibraryGame>(
            predicate: #Predicate<LibraryGame> { $0.coverImageURLString == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        descriptor.fetchLimit = 80

        let games = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        let retryInterval: TimeInterval = 24 * 3600

        let candidates = games.filter { g in
            if let t = g.metadataLastFetchAt {
                return now.timeIntervalSince(t) > retryInterval
            }
            return true
        }

        for game in candidates.prefix(3) {
            if Task.isCancelled { break }
            await fetchAndSave(gameID: game.id, container: container)
            try? await Task.sleep(for: .milliseconds(450))
        }
    }

    private func fetchAndSave(gameID: UUID, container: ModelContainer) async {
        let context = container.mainContext
        var desc = FetchDescriptor<LibraryGame>(predicate: #Predicate { $0.id == gameID })
        desc.fetchLimit = 1
        guard let game = try? context.fetch(desc).first else { return }

        let romStem = URL(fileURLWithPath: game.romPath).deletingPathExtension().lastPathComponent
        let searchTitle = game.libraryListTitle
        if let localCover = localCoverForGame(path: game.romPath, title: searchTitle, romStem: romStem) {
            var options = game.coverImageOptions
            let candidate = localCover.absoluteString
            if !options.contains(candidate) {
                options.insert(candidate, at: 0)
                game.coverImageOptions = options
            } else if game.coverImageURLString == nil {
                game.coverImageURLString = candidate
            }
            game.metadataLastFetchAt = Date()
            try? context.save()
            return
        }

        guard MetadataCredentials.isConfigured else {
            game.metadataLastFetchAt = Date()
            try? context.save()
            return
        }
        do {
            guard let result = try await MetadataService.fetchMetadata(
                displayTitle: searchTitle,
                romFileNameStem: romStem,
                platformHint: game.platformHint
            ) else {
                game.metadataLastFetchAt = Date()
                try context.save()
                return
            }

            game.title = result.normalizedTitle
            if let url = result.coverImageURL {
                game.coverImageURLString = url.absoluteString
            }
            game.metadataLastFetchAt = Date()
            try context.save()
        } catch {
            game.metadataLastFetchAt = Date()
            try? context.save()
            NSLog("Metadata fetch failed: %@", error.localizedDescription)
        }
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
