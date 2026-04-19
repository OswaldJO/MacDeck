import Foundation
import SwiftData

/// User-defined emulator: binary path + how to pass the ROM and optional args.
@Model
public final class EmulatorProfile {
    public var id: UUID
    public var name: String
    /// Path to the emulator executable (.app bundle or binary).
    public var executablePath: String
    /// Placeholder `{rom}` is replaced with the game file path when launching.
    public var launchArgumentTemplate: String
    public var sortOrder: Int
    public var dateCreated: Date

    @Relationship(deleteRule: .cascade, inverse: \GameFolderPath.emulator)
    public var folderPaths: [GameFolderPath] = []

    public init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        launchArgumentTemplate: String = "\"{rom}\"",
        sortOrder: Int = 0,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.launchArgumentTemplate = launchArgumentTemplate
        self.sortOrder = sortOrder
        self.dateCreated = dateCreated
    }
}
