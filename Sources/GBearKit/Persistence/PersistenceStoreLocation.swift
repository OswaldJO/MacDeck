import Foundation

/// Stable on-disk URL for the SwiftData store (inspectable in Finder vs the default opaque path).
public enum PersistenceStoreLocation {
    private static let legacyFolderName = "MacGameLibrary"
    private static let folderName = "GBear"

    public static var directoryURL: URL {
        migrateLegacyApplicationSupportIfNeeded()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var storeFileURL: URL {
        directoryURL.appending(path: "GameLibrary.store")
    }

    /// One-time move from the pre-rename Application Support folder.
    private static func migrateLegacyApplicationSupportIfNeeded() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = base.appending(path: legacyFolderName, directoryHint: .isDirectory)
        let current = base.appending(path: folderName, directoryHint: .isDirectory)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: legacy.path, isDirectory: &isDir), isDir.boolValue else { return }
        if fm.fileExists(atPath: current.path) { return }
        try? fm.moveItem(at: legacy, to: current)
    }
}
