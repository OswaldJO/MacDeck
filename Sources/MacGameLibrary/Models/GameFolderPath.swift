import Foundation
import SwiftData

/// A folder on disk whose files should be associated with one emulator when scanning.
@Model
public final class GameFolderPath {
    public var id: UUID
    public var folderPath: String
    public var emulator: EmulatorProfile?
    public var sortOrder: Int
    public var dateAdded: Date

    public init(
        id: UUID = UUID(),
        folderPath: String,
        emulator: EmulatorProfile?,
        sortOrder: Int = 0,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.folderPath = folderPath
        self.emulator = emulator
        self.sortOrder = sortOrder
        self.dateAdded = dateAdded
    }
}
