import AppKit
import ApplicationServices
import Foundation

/// macOS Accessibility trust for synthetic pointer events (phone touch → Mac cursor).
enum AccessibilityPermission {
    /// Human-readable name shown in System Settings (matches `CFBundleDisplayName`).
    static let settingsAppName = "Mac Game Library"

    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and registers this app in the Accessibility list when needed.
    @MainActor
    static func promptIfNeeded() {
        // String key matches `kAXTrustedCheckOptionPrompt` (avoid non-Sendable global in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openSystemSettings() {
        let urlString: String
        if #available(macOS 13.0, *) {
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
