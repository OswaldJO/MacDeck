import AppKit
import Foundation

enum GameLaunchError: LocalizedError {
    case missingEmulator
    case missingRom
    case invalidExecutable
    case unsupportedStandaloneTarget

    var errorDescription: String? {
        switch self {
        case .missingEmulator: return "No emulator is assigned to this game."
        case .missingRom: return "The game file could not be found."
        case .invalidExecutable: return "The emulator path is not valid."
        case .unsupportedStandaloneTarget: return "The selected Mac game path could not be launched."
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
        DebugLog.log("Launch requested: title=\(game.title) romPath=\(game.romPath)")
        let romURL = URL(fileURLWithPath: game.romPath)
        let standardizedPath = (romURL.path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: standardizedPath) else {
            DebugLog.log("Launch failed: missing ROM at \(standardizedPath)")
            throw GameLaunchError.missingRom
        }
        if game.emulator == nil && game.emulatorUUID == nil {
            if let epicAppName = game.epicAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !epicAppName.isEmpty {
                if launchViaEpicLauncher(appName: epicAppName) {
                    return
                }
            }
            try launchStandaloneTarget(at: URL(fileURLWithPath: standardizedPath))
            return
        }
        guard let emulator = game.emulator else {
            DebugLog.log("Launch failed: missing emulator")
            throw GameLaunchError.missingEmulator
        }

        let exe = URL(fileURLWithPath: emulator.executablePath)
        guard FileManager.default.fileExists(atPath: exe.path) else {
            DebugLog.log("Launch failed: missing emulator executable at \(exe.path)")
            throw GameLaunchError.invalidExecutable
        }

        let substituted = substituteTemplate(emulator.launchArgumentTemplate, gameFilePath: standardizedPath)
        let parts = parseArguments(substituted)
        let resolvedExe = resolvedExecutableURL(exe)
        DebugLog.log("Resolved emulator=\(resolvedExe.path)")
        DebugLog.log("Launch template=\(emulator.launchArgumentTemplate)")
        DebugLog.log("Launch substituted=\(substituted)")
        DebugLog.log("Launch args=\(parts.joined(separator: " | "))")

        // For already-running .app emulators (e.g. RPCS3), launching a second process can fail
        // with single-instance locks. Send an "open document" event to the running app instead.
        if resolvedExe.pathExtension.lowercased() == "app",
           let runningApp = runningApplication(forBundlePath: resolvedExe.path) {
            DebugLog.log("Emulator already running (pid=\(runningApp.processIdentifier)); using open document event")
            registerLaunchedApplication(runningApp)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: standardizedPath)], withApplicationAt: resolvedExe, configuration: config) { _, error in
                if let error {
                    NSLog("Launch error: \(error.localizedDescription)")
                    DebugLog.log("Open document callback error: \(error.localizedDescription)")
                } else {
                    DebugLog.log("Open document callback succeeded")
                }
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = parts

        NSWorkspace.shared.openApplication(
            at: resolvedExe,
            configuration: configuration
        ) { runningApp, error in
            Task { @MainActor in
                if let error {
                    NSLog("Launch error: \(error.localizedDescription)")
                    DebugLog.log("openApplication callback error: \(error.localizedDescription)")
                    return
                }
                guard let runningApp else {
                    DebugLog.log("openApplication callback returned nil app")
                    return
                }
                DebugLog.log("openApplication callback success pid=\(runningApp.processIdentifier)")
                registerLaunchedApplication(runningApp)
            }
        }
    }

    private static func registerLaunchedApplication(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0 else { return }

        let inserted = trackedLaunchPIDs.insert(pid).inserted
        if inserted {
            DebugLog.log("Tracking launched app pid=\(pid); hiding launcher app")
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
        DebugLog.log("Launched app terminated pid=\(pid); remaining tracked=\(trackedLaunchPIDs.count)")

        if trackedLaunchPIDs.isEmpty {
            DebugLog.log("No tracked launches remaining; unhiding launcher app")
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

    private static func runningApplication(forBundlePath bundlePath: String) -> NSRunningApplication? {
        let target = (bundlePath as NSString).standardizingPath
        return NSWorkspace.shared.runningApplications.first { app in
            guard let bundleURL = app.bundleURL else { return false }
            let runningPath = (bundleURL.path as NSString).standardizingPath
            return runningPath == target
        }
    }

    private static func launchStandaloneTarget(at url: URL) throws {
        let standardizedPath = (url.path as NSString).standardizingPath
        let standardizedURL = URL(fileURLWithPath: standardizedPath)
        DebugLog.log("Standalone launch target=\(standardizedPath)")

        if standardizedURL.pathExtension.lowercased() == "app" {
            NSWorkspace.shared.openApplication(
                at: standardizedURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { runningApp, error in
                Task { @MainActor in
                    if let error {
                        NSLog("Standalone launch error: \(error.localizedDescription)")
                        DebugLog.log("Standalone openApplication callback error: \(error.localizedDescription)")
                        return
                    }
                    guard let runningApp else {
                        DebugLog.log("Standalone openApplication callback returned nil app")
                        return
                    }
                    DebugLog.log("Standalone openApplication callback success pid=\(runningApp.processIdentifier)")
                    registerLaunchedApplication(runningApp)
                }
            }
            return
        }

        if NSWorkspace.shared.open(standardizedURL) {
            DebugLog.log("Standalone open succeeded via NSWorkspace.open")
            return
        }
        DebugLog.log("Standalone launch failed for path=\(standardizedPath)")
        throw GameLaunchError.unsupportedStandaloneTarget
    }

    private static func launchViaEpicLauncher(appName: String) -> Bool {
        let escaped = appName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appName
        guard let launchURL = URL(string: "com.epicgames.launcher://apps/\(escaped)?action=launch&silent=true") else {
            return false
        }
        let didOpen = NSWorkspace.shared.open(launchURL)
        DebugLog.log("Epic launch uri appName=\(appName) opened=\(didOpen)")
        return didOpen
    }

}
