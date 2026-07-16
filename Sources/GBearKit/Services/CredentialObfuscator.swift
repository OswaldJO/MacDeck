import Foundation

/// Reversible obfuscation for embedded API secrets (not encryption — keeps plaintext out of source/git).
enum CredentialObfuscator {
    private static let seed = Array("com.local.MacGameLibraryApp.ScreenScraper".utf8)

    static func decode(_ obfuscated: [UInt8]) -> String? {
        guard !obfuscated.isEmpty else { return nil }
        let bytes = obfuscated.enumerated().map { index, byte in
            byte ^ seed[index % seed.count] ^ UInt8((index * 31) & 0xFF)
        }
        return String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
