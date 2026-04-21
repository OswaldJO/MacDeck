import Foundation
import SwiftData

/// User-defined emulator: binary path + how to pass the ROM and optional args.
@Model
public final class EmulatorProfile {
    public var id: UUID
    public var name: String
    /// Path to the emulator executable (.app bundle or binary).
    public var executablePath: String
    /// Playnite-style `{ImagePath}` (and `{rom}` / `{ROM}` aliases) is replaced with the game file path when launching.
    public var launchArgumentTemplate: String
    /// Comma-separated extensions (no dots) used by path scans for this emulator. Empty/nil = global defaults.
    public var supportedFileTypesCSV: String?
    public var sortOrder: Int
    public var dateCreated: Date

    @Relationship(deleteRule: .cascade, inverse: \GameFolderPath.emulator)
    public var folderPaths: [GameFolderPath] = []

    public init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        launchArgumentTemplate: String = "\"{ImagePath}\"",
        supportedFileTypesCSV: String? = nil,
        sortOrder: Int = 0,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.launchArgumentTemplate = launchArgumentTemplate
        self.supportedFileTypesCSV = supportedFileTypesCSV
        self.sortOrder = sortOrder
        self.dateCreated = dateCreated
    }
}


extension EmulatorProfile {
    /// Lowercased extensions (no dots) parsed from `supportedFileTypesCSV`.
    public var supportedFileTypesSet: Set<String> {
        Set((supportedFileTypesCSV ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty })
    }
}
