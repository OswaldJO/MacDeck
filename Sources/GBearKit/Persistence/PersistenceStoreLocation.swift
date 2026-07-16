import Foundation

/// Stable on-disk URL for the SwiftData store (inspectable in Finder vs the default opaque path).
public enum PersistenceStoreLocation {
    public static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: "MacGameLibrary", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var storeFileURL: URL {
        directoryURL.appending(path: "GameLibrary.store")
    }
}
