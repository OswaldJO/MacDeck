import Foundation
import SwiftData

/// `"games"` = ROM scan roots; `"covers"` = image folders matched to ROMs by file name (stem).
public enum GameFolderPurpose: String, Codable, CaseIterable {
    case games
    case covers
    case excludes
}

/// A folder on disk whose files should be associated with one emulator when scanning.
@Model
public final class GameFolderPath {
    public var id: UUID
    public var folderPath: String
    public var emulator: EmulatorProfile?
    public var sortOrder: Int
    public var dateAdded: Date
    /// `nil` or `"games"` = ROM roots; `"covers"` = local cover art directories.
    public var folderPurpose: String?

    public init(
        id: UUID = UUID(),
        folderPath: String,
        emulator: EmulatorProfile?,
        sortOrder: Int = 0,
        dateAdded: Date = Date(),
        folderPurpose: String? = GameFolderPurpose.games.rawValue
    ) {
        self.id = id
        self.folderPath = folderPath
        self.emulator = emulator
        self.sortOrder = sortOrder
        self.dateAdded = dateAdded
        self.folderPurpose = folderPurpose
    }

    public var resolvedPurpose: GameFolderPurpose {
        guard let folderPurpose, let p = GameFolderPurpose(rawValue: folderPurpose) else {
            return .games
        }
        return p
    }
}
