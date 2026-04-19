import Foundation

/// Fetches game metadata and cover art. Wire to IGDB, TheGamesDB, ScreenScraper, etc.
enum MetadataService {
    /// Placeholder: returns nil until you connect an API (see project scope).
    static func fetchMetadata(title: String, platformHint: String?) async throws -> MetadataResult? {
        nil
    }
}

struct MetadataResult: Sendable {
    var normalizedTitle: String
    var coverImageURL: URL?
}
