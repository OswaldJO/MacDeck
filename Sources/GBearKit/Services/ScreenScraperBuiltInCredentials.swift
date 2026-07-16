import Foundation

/// Obfuscated ScreenScraper developer credentials baked into the app.
/// Generate byte arrays with `Scripts/obfuscate-screenscraper-credential.swift` (never commit plaintext).
enum ScreenScraperBuiltInCredentials {
    private static let obfuscatedDevID: [UInt8] = [51, 17, 61, 23, 113, 191, 176, 214, 243, 115, 20, 71, 127]
    private static let obfuscatedDevPassword: [UInt8] = [21, 32, 41, 32, 104, 150, 189, 137, 167, 126, 25]

    static var devID: String? {
        CredentialObfuscator.decode(obfuscatedDevID)
    }

    static var devPassword: String? {
        CredentialObfuscator.decode(obfuscatedDevPassword)
    }

    static var isConfigured: Bool {
        devID != nil && devPassword != nil
    }
}
