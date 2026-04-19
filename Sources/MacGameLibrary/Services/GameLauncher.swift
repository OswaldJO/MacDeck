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

/// Launches a ROM using the configured emulator and `{rom}` template.
enum GameLauncher {
    static func launch(game: LibraryGame) throws {
        guard let emulator = game.emulator else {
            throw GameLaunchError.missingEmulator
        }
        let romURL = URL(fileURLWithPath: game.romPath)
        guard FileManager.default.fileExists(atPath: romURL.path) else {
            throw GameLaunchError.missingRom
        }

        let exe = URL(fileURLWithPath: emulator.executablePath)
        guard FileManager.default.fileExists(atPath: exe.path) else {
            throw GameLaunchError.invalidExecutable
        }

        let substituted = emulator.launchArgumentTemplate
            .replacingOccurrences(of: "{rom}", with: romURL.path)

        let parts = parseArguments(substituted)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = parts

        NSWorkspace.shared.openApplication(
            at: resolvedExecutableURL(exe),
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("Launch error: \(error.localizedDescription)")
            }
        }
    }

    /// If user picked MyEmu.app, open the bundle’s executable; otherwise use path as-is.
    private static func resolvedExecutableURL(_ url: URL) -> URL {
        if url.pathExtension.lowercased() == "app" {
            return url
        }
        return url
    }

    private static func parseArguments(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Simple split; a future version can use a proper shell-style parser.
        return trimmed.split(separator: " ").map(String.init)
    }
}
