import Foundation

/// ScreenScraper API v2 client (https://www.screenscraper.fr/webapi2.php).
enum ScreenScraperClient {
    enum ScreenScraperError: Error, LocalizedError {
        case missingCredentials
        case invalidURL
        case http(Int)
        case decoding
        case noResults

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "ScreenScraper credentials are missing."
            case .invalidURL:
                return "ScreenScraper URL is invalid."
            case .http(let code):
                return "ScreenScraper HTTP \(code)"
            case .decoding:
                return "ScreenScraper response could not be decoded."
            case .noResults:
                return "No ScreenScraper match for this title."
            }
        }
    }

    private static let baseURL = "https://api.screenscraper.fr/api2/jeuRecherche.php"
    private static let softName = "PlayniteMac"

    static func fetchCoverAndTitle(searchQuery: String) async throws -> (title: String, coverURL: URL?) {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScreenScraperError.noResults }
        guard let devID = MetadataCredentials.screenScraperDevID,
              let devPassword = MetadataCredentials.screenScraperDevPassword else {
            throw ScreenScraperError.missingCredentials
        }

        var components = URLComponents(string: baseURL)
        components?.queryItems = buildQueryItems(
            devID: devID,
            devPassword: devPassword,
            userID: MetadataCredentials.screenScraperUserID,
            userPassword: MetadataCredentials.screenScraperUserPassword,
            search: trimmed
        )
        guard let url = components?.url else { throw ScreenScraperError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ScreenScraperError.http(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw ScreenScraperError.http(http.statusCode) }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ScreenScraperError.decoding
        }

        guard let game = firstGame(in: jsonObject) else { throw ScreenScraperError.noResults }
        let title = extractedTitle(from: game) ?? searchQuery
        let cover = extractedCoverURL(from: game)
        return (title, cover)
    }

    private static func buildQueryItems(
        devID: String,
        devPassword: String,
        userID: String?,
        userPassword: String?,
        search: String
    ) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "devid", value: devID),
            URLQueryItem(name: "devpassword", value: devPassword),
            URLQueryItem(name: "softname", value: softName),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "recherche", value: search)
        ]
        if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
            queryItems.append(URLQueryItem(name: "ssid", value: userID))
        }
        if let userPassword = userPassword?.trimmingCharacters(in: .whitespacesAndNewlines), !userPassword.isEmpty {
            queryItems.append(URLQueryItem(name: "sspassword", value: userPassword))
        }
        return queryItems
    }

    private static func firstGame(in json: Any) -> [String: Any]? {
        guard let root = json as? [String: Any] else { return nil }
        if let response = root["response"] as? [String: Any] {
            if let jeux = response["jeux"] as? [[String: Any]], let first = jeux.first {
                return first
            }
            if let jeu = response["jeu"] as? [String: Any] {
                return jeu
            }
        }
        if let jeux = root["jeux"] as? [[String: Any]], let first = jeux.first {
            return first
        }
        if let jeu = root["jeu"] as? [String: Any] {
            return jeu
        }
        return nil
    }

    private static func extractedTitle(from game: [String: Any]) -> String? {
        if let nom = game["nom"] as? String, !nom.isEmpty { return nom }
        if let names = game["noms"] as? [String: Any] {
            let preferred = ["nom_us", "nom_en", "nom_eu", "nom_wor", "nom_ss"]
            for key in preferred {
                if let value = names[key] as? String, !value.isEmpty { return value }
            }
            for value in names.values {
                if let text = value as? String, !text.isEmpty { return text }
            }
        }
        return nil
    }

    private static func extractedCoverURL(from game: [String: Any]) -> URL? {
        guard let medias = game["medias"] else { return nil }
        let preferredKeyFragments = [
            "media_box-2d",
            "media_box-2d_",
            "media_box2d",
            "media_wheel",
            "media_marquee",
            "media_ss",
            "media_sstitle",
            "media_fanart"
        ]
        return firstURL(in: medias, keyFragmentsInPriority: preferredKeyFragments)
    }

    private static func firstURL(in object: Any, keyFragmentsInPriority fragments: [String]) -> URL? {
        if let dict = object as? [String: Any] {
            let sorted = dict.keys.sorted()
            for fragment in fragments {
                for key in sorted where key.lowercased().contains(fragment) {
                    if let url = valueAsURL(dict[key]) {
                        return url
                    }
                }
            }
            for key in sorted {
                if let url = firstURL(in: dict[key] as Any, keyFragmentsInPriority: fragments) {
                    return url
                }
            }
        } else if let list = object as? [Any] {
            for item in list {
                if let url = firstURL(in: item, keyFragmentsInPriority: fragments) {
                    return url
                }
            }
        }
        return nil
    }

    private static func valueAsURL(_ value: Any?) -> URL? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return nil
    }
}
