import Foundation
import SwiftData

/// Infers which emulator owns a ROM from configured Paths scan roots (longest matching folder wins).
enum RomPathPlatformResolver {
    static func emulator(forRomPath romPath: String, context: ModelContext) -> EmulatorProfile? {
        let normalizedRom = normalizedPath(romPath)
        guard !normalizedRom.isEmpty else { return nil }

        let pathEntries = (try? context.fetch(FetchDescriptor<GameFolderPath>())) ?? []
        let emulators = (try? context.fetch(FetchDescriptor<EmulatorProfile>())) ?? []
        var roots: [(root: String, emulator: EmulatorProfile, purpose: GameFolderPurpose)] = []

        for entry in pathEntries {
            guard let emulator = entry.emulator else { continue }
            roots.append((normalizedPath(entry.folderPath), emulator, entry.resolvedPurpose))
        }
        for emulator in emulators {
            for entry in emulator.folderPaths {
                roots.append((normalizedPath(entry.folderPath), emulator, entry.resolvedPurpose))
            }
        }

        let gameRoots = roots.filter { $0.purpose == .games }
        let excludeRoots = roots.filter { $0.purpose == .excludes }

        var best: (rootLength: Int, emulator: EmulatorProfile)?
        var seenRoots = Set<String>()
        for candidate in gameRoots {
            let key = "\(candidate.emulator.id.uuidString)|\(candidate.root)"
            guard seenRoots.insert(key).inserted else { continue }
            guard isPath(normalizedRom, inside: candidate.root) else { continue }

            let excluded = excludeRoots
                .filter { $0.emulator.id == candidate.emulator.id }
                .map(\.root)
            if isPath(normalizedRom, insideAny: excluded) { continue }

            if best == nil || candidate.root.count > best!.rootLength {
                best = (candidate.root.count, candidate.emulator)
            }
        }
        return best?.emulator
    }

    private static func normalizedPath(_ path: String) -> String {
        var normalized = (path as NSString).standardizingPath
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }

    private static func isPath(_ path: String, inside root: String) -> Bool {
        guard !root.isEmpty else { return false }
        if path == root { return true }
        return path.hasPrefix(root + "/")
    }

    private static func isPath(_ path: String, insideAny roots: [String]) -> Bool {
        roots.contains { isPath(path, inside: $0) }
    }
}
