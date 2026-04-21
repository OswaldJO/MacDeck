import AppKit
import Foundation

enum GameLaunchError: LocalizedError {
    case missingEmulator
    case missingRom
    case invalidExecutable

    var errorDescription: String? {
        switch self {
        case .missingEmulator: return "No emulator is assigned to this game."
        case .missingRom: return "The game file could not be found."
        case .invalidExecutable: return "The emulator path is not valid."
        }
    }
}

/// Launches a ROM using the emulator’s argument template.
/// Playnite uses **`{ImagePath}`** for the game/disc file in profiles ([cmdline arguments](https://github.com/JosefNemec/Playnite/wiki/Cmdline-arguments)).
/// We accept `{ImagePath}` (same as Playnite), `{rom}`, and `{ROM}` interchangeably.
@MainActor
enum GameLauncher {
    /// Running emulator PIDs we are currently tracking for auto-hide/restore.
    private static var trackedLaunchPIDs: Set<pid_t> = []
    /// Notification tokens retained while tracking launched emulator processes.
    private static var terminationObservers: [NSObjectProtocol] = []

    static func launch(game: LibraryGame) throws {
        guard let emulator = game.emulator else {
            throw GameLaunchError.missingEmulator
        }
        let romURL = URL(fileURLWithPath: game.romPath)
        let standardizedPath = (romURL.path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: standardizedPath) else {
            throw GameLaunchError.missingRom
        }

        let exe = URL(fileURLWithPath: emulator.executablePath)
        guard FileManager.default.fileExists(atPath: exe.path) else {
            throw GameLaunchError.invalidExecutable
        }

        let substituted = substituteTemplate(emulator.launchArgumentTemplate, gameFilePath: standardizedPath)
        let parts = parseArguments(substituted)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = parts

        NSWorkspace.shared.openApplication(
            at: resolvedExecutableURL(exe),
            configuration: configuration
        ) { runningApp, error in
            if let error {
                NSLog("Launch error: \(error.localizedDescription)")
                return
            }
            guard let runningApp else {
                return
            }
            Task { @MainActor in
                registerLaunchedApplication(runningApp)
            }
        }
    }

    private static func registerLaunchedApplication(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0 else { return }

        let inserted = trackedLaunchPIDs.insert(pid).inserted
        if inserted {
            NSApp.hide(nil)
        }

        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard terminated.processIdentifier == pid else { return }
            Task { @MainActor in
                unregisterLaunchedApplication(pid: pid)
            }
        }
        terminationObservers.append(observer)
    }

    private static func unregisterLaunchedApplication(pid: pid_t) {
        guard trackedLaunchPIDs.contains(pid) else { return }
        trackedLaunchPIDs.remove(pid)

        if trackedLaunchPIDs.isEmpty {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Remove stale observers after each termination.
        let center = NSWorkspace.shared.notificationCenter
        terminationObservers.forEach { center.removeObserver($0) }
        terminationObservers.removeAll()

        // Re-register remaining tracked PIDs to keep monitoring if multiple launches overlap.
        for trackedPID in trackedLaunchPIDs {
            let observer = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                guard terminated.processIdentifier == trackedPID else { return }
                Task { @MainActor in
                    unregisterLaunchedApplication(pid: trackedPID)
                }
            }
            terminationObservers.append(observer)
        }
    }

    /// Normalizes Playnite’s `{ImagePath}` and common aliases to an internal token, then substitutes the file path.
    /// Quoting rules match Playnite: use `"{ImagePath}"` in the profile when the path can contain spaces.
    private static func substituteTemplate(_ template: String, gameFilePath: String) -> String {
        let trimmed = expandPlayniteStylePlaceholders(template.trimmingCharacters(in: .whitespacesAndNewlines))
        if trimmed.isEmpty {
            return "\"\(gameFilePath)\""
        }
        guard trimmed.contains("{rom}") else {
            return trimmed
        }
        let userQuotedPlaceholder = trimmed.contains("\"{rom}\"")
        let pathNeedsQuoting = gameFilePath.contains(where: \.isWhitespace)
        if pathNeedsQuoting && !userQuotedPlaceholder {
            return trimmed.replacingOccurrences(of: "{rom}", with: "\"\(gameFilePath)\"")
        }
        return trimmed.replacingOccurrences(of: "{rom}", with: gameFilePath)
    }

    /// Maps Playnite’s `{ImagePath}` and `{ROM}` to the same internal `{rom}` token before path substitution.
    private static func expandPlayniteStylePlaceholders(_ s: String) -> String {
        s
            .replacingOccurrences(of: "{ImagePath}", with: "{rom}")
            .replacingOccurrences(of: "{ROM}", with: "{rom}")
    }

    /// Splits like a minimal shell: spaces separate tokens; text inside `"` is one token (no quotes in argv).
    private static func parseArguments(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [String] = []
        var current = ""
        var inDoubleQuotes = false

        for char in trimmed {
            if char == "\"" {
                if inDoubleQuotes {
                    result.append(current)
                    current = ""
                    inDoubleQuotes = false
                } else {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                    inDoubleQuotes = true
                }
            } else if char.isWhitespace && !inDoubleQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func resolvedExecutableURL(_ url: URL) -> URL {
        if url.pathExtension.lowercased() == "app" {
            return url
        }
        return url
    }
}
