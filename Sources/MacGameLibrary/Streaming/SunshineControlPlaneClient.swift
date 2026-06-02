import Foundation

/// Sunshine HTTPS dashboard API (`/api/*` on port 47990 by default).
struct SunshineControlPlaneClient: StreamingControlPlaneClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession

    init(
        baseURL: URL = StreamingHostSettings.controlPlaneBaseURL,
        username: String = StreamingHostSettings.username,
        password: String = StreamingHostSettings.password,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            self.session = URLSession(configuration: config, delegate: SunshineTLSDelegate(), delegateQueue: nil)
        }
    }

    func ping() async throws -> Bool {
        let url = baseURL.appending(path: "api/clients/list")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorize(&request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200 ..< 300).contains(http.statusCode)
    }

    func submitPairingPIN(_ pin: String, deviceName: String) async throws {
        let url = baseURL.appending(path: "api/pin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        let body: [String: String] = [
            "pin": pin,
            "name": deviceName.isEmpty ? "Companion" : deviceName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamingControlPlaneError.hostUnreachable
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw StreamingControlPlaneError.pairingFailed(detail)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? Bool, status == false {
            throw StreamingControlPlaneError.pairingFailed("Sunshine rejected the PIN (is the companion waiting to pair?)")
        }
    }

    func fetchPairedClientNames() async throws -> [String] {
        let url = baseURL.appending(path: "api/clients/list")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw StreamingControlPlaneError.hostUnreachable
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let certs = json["named_certs"] as? [[String: Any]] else {
            return []
        }
        return certs.compactMap { $0["name"] as? String }
    }

    private func authorize(_ request: inout URLRequest) {
        guard !username.isEmpty else { return }
        let cred = "\(username):\(password)"
        guard let encoded = cred.data(using: .utf8)?.base64EncodedString() else { return }
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }
}
