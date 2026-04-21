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
        "nsp", "xci", "wua",
        "zip", "7z", "rar",
        "psx", "img", "mdf", "bin",
        "lnx", "a26", "a52", "int",
        "crt", "tap", "prg", "d64", "t64",
        "rom", "mx1", "mx2",
        "wad", "pk3", "iwad"
    ]

    private static let coverImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "tif", "tiff"
    ]
    /// Restrictive file-based imports for PS3/RPCS3 scanners to avoid importing random assets from `dev_hdd0/game`.
    private static let ps3FileExtensions: Set<String> = ["iso"]

    private struct PS3FolderMetadata {
        let title: String?
        let titleID: String?
        let category: String?
    }

    /// Returns an executable PS3 target path when this folder looks like a PS3 disc dump or RPCS3 installed title.
    private static func ps3LaunchPathIfPresent(for folder: URL) -> URL? {
        let fm = FileManager.default
        let candidatePaths = [
            // Disc dump structure: <Game>/PS3_GAME/USRDIR/EBOOT.BIN
            folder.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN").path,
            // RPCS3 installed structure: <TitleID>/USRDIR/EBOOT.BIN
            folder.appendingPathComponent("USRDIR/EBOOT.BIN").path
        ]
        for p in candidatePaths {
            if fm.fileExists(atPath: p) {
                return URL(fileURLWithPath: (p as NSString).standardizingPath)
            }
        }
        return nil
    }

    private static func ps3Metadata(for folder: URL) -> PS3FolderMetadata? {
        let sfoCandidates = [
            folder.appendingPathComponent("PS3_GAME/PARAM.SFO"),
            folder.appendingPathComponent("PARAM.SFO")
        ]

        for url in sfoCandidates {
            guard let data = try? Data(contentsOf: url),
                  let fields = parsePS3SFO(data) else { continue }

            let title = fields["TITLE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleID = fields["TITLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = fields["CATEGORY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PS3FolderMetadata(
                title: (title?.isEmpty == false ? title : nil),
                titleID: (titleID?.isEmpty == false ? titleID : nil),
                category: (category?.isEmpty == false ? category : nil)
            )
        }
        return nil
    }

    /// Resolves a readable title for PS3 content from PARAM.SFO (TITLE > TITLE_ID > fallback folder name).
    private static func ps3DisplayTitle(for folder: URL) -> String {
        let fallback = folder.lastPathComponent
        guard let meta = ps3Metadata(for: folder) else { return fallback }
        if let title = meta.title { return title }
        if let titleID = meta.titleID { return titleID }
        return fallback
    }

    /// Keeps scan results focused on playable titles and avoids importing game data/patch/DLC folders.
    /// Common playable categories are `DG` (disc game) and `HG` (HDD game).
    private static func shouldIncludePS3Folder(_ folder: URL) -> Bool {
        guard let meta = ps3Metadata(for: folder), let category = meta.category?.uppercased() else { return false }
        return category == "DG" || category == "HG"
    }

    private static func isPS3StyleEmulator(_ emulator: EmulatorProfile) -> Bool {
        let name = emulator.name.lowercased()
        let exe = emulator.executablePath.lowercased()
        if name.contains("rpcs3") || name.contains("ps3") { return true }
        if exe.contains("rpcs3") { return true }
        return false
    }

    /// Minimal parser for PS3 PARAM.SFO key/value string fields.
    private static func parsePS3SFO(_ data: Data) -> [String: String]? {
        guard data.count >= 20 else { return nil }

        func u16(_ offset: Int) -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                raw.load(fromByteOffset: offset, as: UInt16.self).littleEndian
            }
        }

        func u32(_ offset: Int) -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                raw.load(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
        }

        guard let magic = u32(0), magic == 0x46535000,
              let keyTableStart = u32(8),
              let dataTableStart = u32(12),
              let count = u32(16) else { return nil }

        var out: [String: String] = [:]
        let base = 20
        let entrySize = 16

        for i in 0..<Int(count) {
            let entry = base + i * entrySize
            guard entry + entrySize <= data.count,
                  let keyOffset = u16(entry),
                  let valueLen = u32(entry + 4),
                  let dataOffset = u32(entry + 12) else { continue }

            let keyStart = Int(keyTableStart) + Int(keyOffset)
            guard keyStart < data.count else { continue }
            let keyEnd = data[keyStart...].firstIndex(of: 0) ?? data.endIndex
            guard keyEnd > keyStart else { continue }
            guard let key = String(data: data[keyStart..<keyEnd], encoding: .utf8), !key.isEmpty else { continue }

            let valueStart = Int(dataTableStart) + Int(dataOffset)
            let safeLen = max(0, Int(valueLen))
            guard valueStart >= 0, valueStart + safeLen <= data.count else { continue }

            var valueData = data[valueStart..<(valueStart + safeLen)]
            while valueData.last == 0 { valueData.removeLast() }
            if let value = String(data: valueData, encoding: .utf8), !value.isEmpty {
                out[key] = value
            }
        }

        return out.isEmpty ? nil : out
    }

    /// Lowercased file name without extension → first matching image URL found (ordered by cover folder `sortOrder`).
    private static func buildCoverIndex(folderEntries: [GameFolderPath]) -> [UUID: [String: URL]] {
        var result: [UUID: [String: URL]] = [:]
        let coverEntries = folderEntries
            .filter { $0.resolvedPurpose == .covers }
            .sorted { $0.sortOrder < $1.sortOrder }

        for entry in coverEntries {
            guard let emulator = entry.emulator else { continue }
            let emuID = emulator.id
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
                guard coverImageExtensions.contains(ext) else { continue }

                let stem = item.deletingPathExtension().lastPathComponent.lowercased()
                guard !stem.isEmpty else { continue }

                var perEmu = result[emuID] ?? [:]
                if perEmu[stem] == nil {
                    let standardized = URL(fileURLWithPath: (item.path as NSString).standardizingPath)
                    perEmu[stem] = standardized
                    result[emuID] = perEmu
                }
            }
        }
        return result
    }

    public static func scan(modelContext: ModelContext) throws -> Int {
        let gamesFetch = FetchDescriptor<LibraryGame>()
        let existingGames = try modelContext.fetch(gamesFetch)
        var existingPaths = Set(
            existingGames.map { ($0.romPath as NSString).standardizingPath }
        )

        let pathsFetch = FetchDescriptor<GameFolderPath>()
        let folderEntries = try modelContext.fetch(pathsFetch)
        let coverIndex = buildCoverIndex(folderEntries: folderEntries)
        let romFolderEntries = folderEntries.filter { $0.resolvedPurpose == .games }

        var maxSort = existingGames.map(\.sortOrder).max() ?? 0
        var added = 0

        for entry in romFolderEntries {
            guard let emulator = entry.emulator else { continue }
            let isPS3Emulator = isPS3StyleEmulator(emulator)
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
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

                if values?.isDirectory == true, let ps3Launch = ps3LaunchPathIfPresent(for: item) {
                    guard shouldIncludePS3Folder(item) else {
                        enumerator.skipDescendants()
                        continue
                    }
                    let standardized = (ps3Launch.path as NSString).standardizingPath
                    guard !existingPaths.contains(standardized) else {
                        enumerator.skipDescendants()
                        continue
                    }
                    existingPaths.insert(standardized)

                    let title = ps3DisplayTitle(for: item)
                    let folderNameKey = item.lastPathComponent.lowercased()
                    let coverURL = coverIndex[emulator.id]?[title.lowercased()] ?? coverIndex[emulator.id]?[folderNameKey]
                    maxSort += 1
                    let game = LibraryGame(
                        title: title,
                        romPath: standardized,
                        emulator: emulator,
                        coverImageURLString: coverURL?.absoluteString,
                        sortOrder: maxSort
                    )
                    modelContext.insert(game)
                    added += 1
                    enumerator.skipDescendants()
                    continue
                }

                guard values?.isRegularFile == true else { continue }

                let ext = item.pathExtension.lowercased()
                if isPS3Emulator {
                    guard ps3FileExtensions.contains(ext) else { continue }
                } else {
                    guard romExtensions.contains(ext) else { continue }
                }

                let standardized = (item.path as NSString).standardizingPath
                guard !existingPaths.contains(standardized) else { continue }
                existingPaths.insert(standardized)

                let title = item.deletingPathExtension().lastPathComponent
                let coverURL = coverIndex[emulator.id]?[title.lowercased()]
                maxSort += 1
                let game = LibraryGame(
                    title: title,
                    romPath: standardized,
                    emulator: emulator,
                    coverImageURLString: coverURL?.absoluteString,
                    sortOrder: maxSort
                )
                modelContext.insert(game)
                added += 1
            }
        }

        var linkedCovers = 0
        let allGames = try modelContext.fetch(gamesFetch)
        for game in allGames {
            guard game.coverImageURLString == nil, let emulator = game.emulator else { continue }
            let romStem = URL(fileURLWithPath: game.romPath).deletingPathExtension().lastPathComponent.lowercased()
            guard let url = coverIndex[emulator.id]?[romStem] else { continue }
            game.coverImageURLString = url.absoluteString
            linkedCovers += 1
        }

        if added > 0 || linkedCovers > 0 {
            try modelContext.save()
        }
        return added
    }
}
