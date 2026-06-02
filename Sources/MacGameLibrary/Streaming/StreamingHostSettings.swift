import Foundation

/// Credentials and URLs for the local Sunshine host (control plane + Moonlight pairing ports).
enum StreamingHostSettings {
    private static let baseURLKey = "streaming.sunshine.baseURL"
    private static let usernameKey = "streaming.sunshine.username"
    private static let passwordKey = "streaming.sunshine.password"
    private static let credsSyncedKey = "streaming.sunshine.credsSynced"

    static var controlPlaneBaseURL: URL {
        let raw = UserDefaults.standard.string(forKey: baseURLKey)
            ?? URL.localhostControlPlane().absoluteString
        return URL(string: raw) ?? URL.localhostControlPlane()
    }

    static func setControlPlaneBaseURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: baseURLKey)
    }

    static var username: String {
        UserDefaults.standard.string(forKey: usernameKey) ?? ""
    }

    static var password: String {
        UserDefaults.standard.string(forKey: passwordKey) ?? ""
    }

    static func setCredentials(username: String, password: String) {
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(password, forKey: passwordKey)
        UserDefaults.standard.set(false, forKey: credsSyncedKey)
    }

    static var hasCredentials: Bool {
        !username.isEmpty && !password.isEmpty
    }

    /// True when Playnite must run `sunshine --creds` again (new or rotated credentials).
    static var credentialsNeedSunshineSync: Bool {
        !UserDefaults.standard.bool(forKey: credsSyncedKey)
    }

    static func markCredentialsSyncedToSunshine() {
        UserDefaults.standard.set(true, forKey: credsSyncedKey)
    }

    /// Creates control-plane credentials on first use; no Sunshine web UI required.
    static func ensureGeneratedCredentials() {
        guard !hasCredentials else { return }
        let suffix = UUID().uuidString.prefix(8)
        setCredentials(
            username: "playnite",
            password: "pgl-\(suffix)-\(UUID().uuidString.prefix(12))"
        )
    }
}
