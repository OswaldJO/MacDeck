import Foundation

/// Stores Twitch / IGDB API credentials (same flow as Playnite’s IGDB metadata: Twitch Developer app + IGDB API).
enum MetadataCredentials {
    private static let clientIdKey = "Metadata.IGDB.ClientID"
    private static let clientSecretKey = "Metadata.IGDB.ClientSecret"

    static var twitchClientId: String? {
        get { UserDefaults.standard.string(forKey: clientIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: clientIdKey) }
    }

    static var twitchClientSecret: String? {
        get { UserDefaults.standard.string(forKey: clientSecretKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: clientSecretKey) }
    }

    static var isConfigured: Bool {
        twitchClientId != nil && twitchClientSecret != nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
