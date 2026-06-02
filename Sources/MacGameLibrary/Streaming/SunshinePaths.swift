import Foundation

/// Isolated Sunshine config under Application Support (separate from `~/.config/sunshine`).
enum SunshinePaths {
    static let configDirectoryName = "sunshine"
    static let configFileName = "playnite-sunshine.conf"
    static let credentialsFileName = "sunshine_state.json"

    static var configDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appending(path: "MacGameLibrary", directoryHint: .isDirectory)
            .appending(path: configDirectoryName, directoryHint: .isDirectory)
    }

    static var configFile: URL {
        configDirectory.appending(path: configFileName)
    }

    static var credentialsFile: URL {
        configDirectory.appending(path: credentialsFileName)
    }

    static func ensureConfigDirectory() throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }
}
