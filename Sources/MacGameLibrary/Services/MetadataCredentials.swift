import Foundation

/// Stores ScreenScraper API credentials.
enum MetadataCredentials {
    private static let devIDKey = "Metadata.ScreenScraper.DevID"
    private static let devPasswordKey = "Metadata.ScreenScraper.DevPassword"
    private static let userIDKey = "Metadata.ScreenScraper.UserID"
    private static let userPasswordKey = "Metadata.ScreenScraper.UserPassword"

    static var screenScraperDevID: String? {
        get { UserDefaults.standard.string(forKey: devIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: devIDKey) }
    }

    static var screenScraperDevPassword: String? {
        get { UserDefaults.standard.string(forKey: devPasswordKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: devPasswordKey) }
    }

    static var screenScraperUserID: String? {
        get { UserDefaults.standard.string(forKey: userIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: userIDKey) }
    }

    static var screenScraperUserPassword: String? {
        get { UserDefaults.standard.string(forKey: userPasswordKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        set { UserDefaults.standard.set(newValue, forKey: userPasswordKey) }
    }

    static var isConfigured: Bool {
        screenScraperDevID != nil && screenScraperDevPassword != nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
