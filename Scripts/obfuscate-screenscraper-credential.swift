#!/usr/bin/env swift
import Foundation

/// Encode ScreenScraper dev credentials for ScreenScraperBuiltInCredentials.swift.
/// Usage:
///   swift Scripts/obfuscate-screenscraper-credential.swift YOUR_DEV_ID YOUR_DEV_PASSWORD
/// Or (no secrets in shell history):
///   SCREENSCRAPER_DEV_ID=... SCREENSCRAPER_DEV_PASSWORD=... swift Scripts/obfuscate-screenscraper-credential.swift

# Seed must stay stable so ScreenScraperBuiltInCredentials keep decoding.
private let seed = Array("com.local.MacGameLibraryApp.ScreenScraper".utf8)

func encode(_ plaintext: String) -> [UInt8] {
    let bytes = Array(plaintext.utf8)
    return bytes.enumerated().map { index, byte in
        byte ^ seed[index % seed.count] ^ UInt8((index * 31) & 0xFF)
    }
}

func swiftArray(_ bytes: [UInt8]) -> String {
    bytes.map { String($0) }.joined(separator: ", ")
}

let devID = ProcessInfo.processInfo.environment["SCREENSCRAPER_DEV_ID"]
    ?? CommandLine.arguments.dropFirst().first
let devPassword = ProcessInfo.processInfo.environment["SCREENSCRAPER_DEV_PASSWORD"]
    ?? CommandLine.arguments.dropFirst().dropFirst().first

guard let devID, let devPassword, !devID.isEmpty, !devPassword.isEmpty else {
    fputs(
        """
        Usage:
          swift Scripts/obfuscate-screenscraper-credential.swift DEV_ID DEV_PASSWORD

        Or set SCREENSCRAPER_DEV_ID and SCREENSCRAPER_DEV_PASSWORD in the environment.

        Paste the printed arrays into Sources/GBearKit/Services/ScreenScraperBuiltInCredentials.swift

        """,
        stderr
    )
    exit(1)
}

let idBytes = encode(devID)
let passwordBytes = encode(devPassword)

print("// Paste into ScreenScraperBuiltInCredentials.swift (do not commit plaintext credentials).")
print("private static let obfuscatedDevID: [UInt8] = [\(swiftArray(idBytes))]")
print("private static let obfuscatedDevPassword: [UInt8] = [\(swiftArray(passwordBytes))]")
