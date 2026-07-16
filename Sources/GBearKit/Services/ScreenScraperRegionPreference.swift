import Foundation

/// ScreenScraper media/title region short codes (see `regionsListe.php`).
enum ScreenScraperRegionPreference {
    static let defaultRegionCode = "us"

    static let selectableRegions: [(code: String, label: String)] = [
        ("us", "United States"),
        ("eu", "Europe"),
        ("jp", "Japan"),
        ("wor", "World"),
        ("fr", "France"),
        ("de", "Germany"),
        ("es", "Spain"),
        ("it", "Italy"),
        ("pt", "Portugal"),
        ("au", "Australia"),
        ("kr", "Korea"),
        ("ss", "ScreenScraper default"),
    ]

    /// Region order for cover/title fallback: user default, then universal, then any other.
    static func mediaRegionOrder(preferredCode: String?) -> [String] {
        let preferred = preferredCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var order: [String] = []
        if let preferred, !preferred.isEmpty {
            order.append(preferred)
        }
        for code in ["wor", "ss", "us", "eu", "jp", "fr", "de", "es", "it", "pt", "au", "kr"] {
            if !order.contains(code) {
                order.append(code)
            }
        }
        return order
    }
}
