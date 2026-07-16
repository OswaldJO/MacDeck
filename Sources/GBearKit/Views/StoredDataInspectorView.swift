import AppKit
import SwiftData
import SwiftUI

/// Live read-only view of SwiftData contents + store file location (no Xcode console required).
public struct StoredDataInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]
    @Query(sort: \LibraryGame.sortOrder) private var games: [LibraryGame]
    @Query(sort: \GameFolderPath.sortOrder) private var paths: [GameFolderPath]

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Store file") {
                    Text(PersistenceStoreLocation.storeFileURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(PersistenceStoreLocation.storeFileURL.path, forType: .string)
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(
                                PersistenceStoreLocation.storeFileURL.path,
                                inFileViewerRootedAtPath: PersistenceStoreLocation.directoryURL.path
                            )
                        }
                    }
                }

                Section("Emulators (\(emulators.count))") {
                    ForEach(emulators) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.headline)
                            Text(e.executablePath).font(.caption2).foregroundStyle(.secondary)
                            Text(e.launchArgumentTemplate).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("Games (\(games.count))") {
                    ForEach(games) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.headline)
                            Text(g.romPath).font(.caption2).foregroundStyle(.secondary)
                            if let emu = g.emulator {
                                Text("Emulator: \(emu.name)").font(.caption2)
                            } else {
                                Text("Emulator: —").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Paths (\(paths.count))") {
                    ForEach(paths) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.folderPath).font(.caption)
                            if let emu = p.emulator {
                                Text("\(emu.name) · \(p.resolvedPurpose == .covers ? "covers" : "games")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SwiftData contents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
