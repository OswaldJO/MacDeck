import Foundation
import SwiftData

/// Background metadata passes (similar in role to Playnite’s `MetadataDownloader` / library update jobs): periodically fills missing covers via IGDB when credentials are set.
@MainActor
final class MetadataBackgroundFetcher {
    static let shared = MetadataBackgroundFetcher()

    private var loopTask: Task<Void, Never>?
    private var container: ModelContainer?

    private init() {}

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
            guard MetadataCredentials.isConfigured else { return }
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
        guard MetadataCredentials.isConfigured else { return }

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

        do {
            guard let result = try await MetadataService.fetchMetadata(
                displayTitle: game.title,
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
}
