import Foundation
import SwiftData

/// Imports locally installed Epic Games Launcher titles by reading launcher manifests.
enum EpicInstalledGamesImporter {
    struct ImportSummary {
        var added: Int
        var updated: Int

        var hasChanges: Bool { added > 0 || updated > 0 }
    }

    private struct EpicManifest: Decodable {
        var displayName: String?
        var installLocation: String?
        var launchExecutable: String?
        var appName: String?
        var catalogItemId: String?
        var namespaceId: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "DisplayName"
            case installLocation = "InstallLocation"
            case launchExecutable = "LaunchExecutable"
            case appName = "AppName"
            case catalogItemId = "CatalogItemId"
            case namespaceId = "CatalogNamespace"
        }
    }

    static func importInstalledGames(modelContext: ModelContext) throws -> ImportSummary {
        let manifests = loadInstalledManifests()
        guard !manifests.isEmpty else {
            return ImportSummary(added: 0, updated: 0)
        }

        let games = try modelContext.fetch(FetchDescriptor<LibraryGame>())
        let existingByPath = Dictionary(
            uniqueKeysWithValues: games.map { (normalizedPath($0.romPath), $0) }
        )
        var existingEpicByAppName: [String: LibraryGame] = [:]
        for game in games {
            guard let app = game.epicAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !app.isEmpty else { continue }
            existingEpicByAppName[app.lowercased()] = game
        }

        var added = 0
        var updated = 0
        var maxSort = games.map(\.sortOrder).max() ?? -1

        for manifest in manifests {
            guard let normalizedLaunchPath = resolvedLaunchPath(from: manifest),
                  !normalizedLaunchPath.isEmpty else { continue }

            let appName = manifest.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = manifest.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (display?.isEmpty == false ? display! : URL(fileURLWithPath: normalizedLaunchPath).deletingPathExtension().lastPathComponent)

            if let existing = existingByPath[normalizedPath(normalizedLaunchPath)] {
                var touched = false
                if existing.emulatorUUID != nil || existing.emulator != nil {
                    existing.emulatorIDString = nil
                    existing.emulator = nil
                    touched = true
                }
                if existing.title != title {
                    existing.title = title
                    touched = true
                }
                if existing.librarySourceID != "epic" {
                    existing.librarySourceID = "epic"
                    touched = true
                }
                if existing.epicAppName != appName {
                    existing.epicAppName = appName
                    touched = true
                }
                if touched { updated += 1 }
                continue
            }

            if let appName, let existingByApp = existingEpicByAppName[appName.lowercased()] {
                var touched = false
                if existingByApp.romPath != normalizedLaunchPath {
                    existingByApp.romPath = normalizedLaunchPath
                    touched = true
                }
                if existingByApp.title != title {
                    existingByApp.title = title
                    touched = true
                }
                if existingByApp.librarySourceID != "epic" {
                    existingByApp.librarySourceID = "epic"
                    touched = true
                }
                if touched { updated += 1 }
                continue
            }

            maxSort += 1
            let game = LibraryGame(
                title: title,
                romPath: normalizedLaunchPath,
                emulatorIDString: nil,
                emulator: nil,
                platformHint: "PC",
                librarySourceID: "epic",
                epicAppName: appName,
                sortOrder: maxSort
            )
            modelContext.insert(game)
            added += 1
        }

        if added > 0 || updated > 0 {
            try modelContext.save()
        }
        return ImportSummary(added: added, updated: updated)
    }

    private static func loadInstalledManifests() -> [EpicManifest] {
        let base = ("~/Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests" as NSString)
            .expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let baseURL = URL(fileURLWithPath: base)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        var manifests: [EpicManifest] = []
        for file in files where file.pathExtension.lowercased() == "item" {
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? decoder.decode(EpicManifest.self, from: data) else { continue }
            manifests.append(manifest)
        }
        return manifests
    }

    private static func resolvedLaunchPath(from manifest: EpicManifest) -> String? {
        let install = manifest.installLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !install.isEmpty else { return nil }

        let rawLaunch = manifest.launchExecutable?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawLaunch.isEmpty {
            if rawLaunch.hasPrefix("/") {
                let absolute = (rawLaunch as NSString).standardizingPath
                if FileManager.default.fileExists(atPath: absolute) {
                    return absolute
                }
            }
            let joined = ((install as NSString).appendingPathComponent(rawLaunch) as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: joined) {
                return joined
            }
        }

        // Common macOS layout fallback if LaunchExecutable is unavailable.
        if let appURL = firstAppBundle(in: URL(fileURLWithPath: (install as NSString).standardizingPath)) {
            return appURL.path
        }
        return nil
    }

    private static func firstAppBundle(in directory: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        if directory.pathExtension.lowercased() == "app" {
            return directory
        }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for item in items {
            if item.pathExtension.lowercased() == "app" {
                return item
            }
        }
        return nil
    }

    private static func normalizedPath(_ raw: String) -> String {
        var normalized = (raw as NSString).standardizingPath
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }
}
