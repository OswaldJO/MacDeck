import Foundation
import SwiftData

/// One library entry: a ROM/disc image linked to an emulator and optional scraped metadata.
@Model
public final class LibraryGame {
    public var id: UUID
    public var title: String
    /// Absolute path to the ROM or disc image.
    public var romPath: String
    public var emulator: EmulatorProfile?
    /// Remote or cached cover image URL (file:// or https://).
    public var coverImageURLString: String?
    /// Optional platform/system hint for metadata search (e.g. "SNES", "PS2").
    public var platformHint: String?
    public var sortOrder: Int
    public var dateAdded: Date
    public var lastPlayed: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        romPath: String,
        emulator: EmulatorProfile? = nil,
        coverImageURLString: String? = nil,
        platformHint: String? = nil,
        sortOrder: Int = 0,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.romPath = romPath
        self.emulator = emulator
        self.coverImageURLString = coverImageURLString
        self.platformHint = platformHint
        self.sortOrder = sortOrder
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
    }
}
