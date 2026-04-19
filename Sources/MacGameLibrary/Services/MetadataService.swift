import Foundation

/// Fetches game metadata and cover art.
///
/// Playnite uses a **metadata downloader** pipeline with pluggable providers; the built-in **IGDB** plugin talks to IGDB over HTTPS with Twitch credentials ([Playnite metadata plugins](https://api.playnite.link/docs/tutorials/extensions/metadataPlugins.html)).
/// This app uses the same data source: **IGDB v4** with Twitch **client credentials** (no browser login at runtime).
enum MetadataService {
    /// Returns normalized title and optional cover URL, or `nil` if credentials are not configured.
    static func fetchMetadata(displayTitle: String, romFileNameStem: String, platformHint: String?) async throws -> MetadataResult? {
        guard MetadataCredentials.isConfigured else { return nil }
        let fromRom = RomTitleNormalizer.searchQuery(fromFileNameStem: romFileNameStem)
        let fromDisplay = RomTitleNormalizer.searchQuery(fromFileNameStem: displayTitle)
        let query = [fromRom, fromDisplay].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? displayTitle

        let fetched = try await IGDBClient.fetchCoverAndTitle(searchQuery: query)
        return MetadataResult(
            normalizedTitle: fetched.title,
            coverImageURL: fetched.coverURL
        )
    }
}

struct MetadataResult: Sendable {
    var normalizedTitle: String
    var coverImageURL: URL?
}
