import Foundation

/// IGDB API v4 via Twitch OAuth client credentials (documented at https://api-docs.igdb.com).
enum IGDBClient {
    enum IGDBError: Error, LocalizedError {
        case missingCredentials
        case http(Int)
        case decoding
        case noResults

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "IGDB: add Twitch Client ID and Client Secret in Metadata settings."
            case .http(let c):
                return "IGDB HTTP \(c)"
            case .decoding:
                return "IGDB response could not be decoded."
            case .noResults:
                return "No IGDB match for this title."
            }
        }
    }

    private static let tokenURL = URL(string: "https://id.twitch.tv/oauth2/token")!
    private static let gamesURL = URL(string: "https://api.igdb.com/v4/games")!

    private actor TokenBox {
        var accessToken: String?
        var expiresAt: Date?

        func cachedTokenIfValid() -> String? {
            guard let t = accessToken, let e = expiresAt, Date() < e.addingTimeInterval(-120) else { return nil }
            return t
        }

        func store(accessToken: String, expiresAt: Date) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
        }
    }

    private static let tokens = TokenBox()

    /// Returns cover `https` URL and normalized game name from the best search hit.
    static func fetchCoverAndTitle(searchQuery: String) async throws -> (title: String, coverURL: URL?) {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IGDBError.noResults }

        guard let clientId = MetadataCredentials.twitchClientId,
              let secret = MetadataCredentials.twitchClientSecret else {
            throw IGDBError.missingCredentials
        }

        let token = try await accessToken(clientId: clientId, clientSecret: secret)
        let body = """
        search "\(escapeApicalypse(trimmed))";
        fields name,cover.url;
        limit 8;
        """

        var request = URLRequest(url: gamesURL)
        request.httpMethod = "POST"
        request.setValue(clientId, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IGDBError.http(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw IGDBError.http(http.statusCode) }

        let games: [IGDBGameRow]
        do {
            games = try JSONDecoder().decode([IGDBGameRow].self, from: data)
        } catch {
            throw IGDBError.decoding
        }
        guard let first = games.first else { throw IGDBError.noResults }

        let title = first.name ?? searchQuery
        let cover: URL?
        if let raw = first.cover?.url {
            cover = Self.httpsURL(fromIGDBImagePath: raw)
        } else {
            cover = nil
        }

        return (title, cover)
    }

    private static func accessToken(clientId: String, clientSecret: String) async throws -> String {
        if let t = await tokens.cachedTokenIfValid() {
            return t
        }

        var components = URLComponents(url: tokenURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw IGDBError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let tok: TwitchTokenResponse
        do {
            tok = try JSONDecoder().decode(TwitchTokenResponse.self, from: data)
        } catch {
            throw IGDBError.decoding
        }
        let expiry = Date().addingTimeInterval(TimeInterval(tok.expiresIn))
        await tokens.store(accessToken: tok.accessToken, expiresAt: expiry)
        return tok.accessToken
    }

    private static func escapeApicalypse(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func httpsURL(fromIGDBImagePath raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    private struct TwitchTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private struct IGDBGameRow: Decodable {
        let name: String?
        let cover: IGDBCover?

        struct IGDBCover: Decodable {
            let url: String?
        }
    }
}
