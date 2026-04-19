import Foundation
import SwiftData

/// Recursively scans configured folders and inserts new `LibraryGame` rows for recognized ROM-like files.
public enum GamePathScanner {
    /// Common extensions for disc images, archives, and ROMs (lowercase, no dot).
    public static let romExtensions: Set<String> = [
        "nes", "fds", "unf", "unif",
        "smc", "sfc", "fig", "swc", "bs",
        "gb", "gbc", "gba", "nds", "dsi",
        "n64", "z64", "v64",
        "3ds", "cia", "cci", "cxi",
        "md", "smd", "gen", "32x", "sms", "gg", "sg",
        "pce", "sgx", "ngp", "ngc",
        "iso", "gcn", "ciso", "gcz", "rvz", "wbfs", "wad", "dol", "elf",
        "cue", "chd", "gdi", "cdi", "m3u", "pbp",
        "nsp", "xci",
        "zip", "7z", "rar",
        "psx", "img", "mdf", "bin",
        "lnx", "a26", "a52", "int",
        "crt", "tap", "prg", "d64", "t64",
        "rom", "mx1", "mx2",
        "wad", "pk3", "iwad"
    ]

    public static func scan(modelContext: ModelContext) throws -> Int {
        let gamesFetch = FetchDescriptor<LibraryGame>()
        let existingGames = try modelContext.fetch(gamesFetch)
        var existingPaths = Set(
            existingGames.map { ($0.romPath as NSString).standardizingPath }
        )

        let pathsFetch = FetchDescriptor<GameFolderPath>()
        let folderEntries = try modelContext.fetch(pathsFetch)

        var maxSort = existingGames.map(\.sortOrder).max() ?? 0
        var added = 0

        for entry in folderEntries {
            guard let emulator = entry.emulator else { continue }
            let root = URL(fileURLWithPath: entry.folderPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }

                let ext = item.pathExtension.lowercased()
                guard romExtensions.contains(ext) else { continue }

                let standardized = (item.path as NSString).standardizingPath
                guard !existingPaths.contains(standardized) else { continue }
                existingPaths.insert(standardized)

                let title = item.deletingPathExtension().lastPathComponent
                maxSort += 1
                let game = LibraryGame(
                    title: title,
                    romPath: standardized,
                    emulator: emulator,
                    sortOrder: maxSort
                )
                modelContext.insert(game)
                added += 1
            }
        }

        if added > 0 {
            try modelContext.save()
        }
        return added
    }
}
