import AppKit
import SwiftData
import SwiftUI

struct PathsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]
    @Query(sort: \GameFolderPath.sortOrder) private var allFolderPaths: [GameFolderPath]

    @State private var selectedEmulatorID: UUID?

    /// Resolved picker value when `emulators` is non-empty (avoids Picker tag/`nil` mismatch).
    private var effectiveEmulatorID: UUID {
        guard let first = emulators.first else {
            return UUID()
        }
        if let id = selectedEmulatorID, emulators.contains(where: { $0.id == id }) {
            return id
        }
        return first.id
    }

    private var pathsForSelection: [GameFolderPath] {
        guard !emulators.isEmpty else { return [] }
        let id = effectiveEmulatorID
        return allFolderPaths.filter { $0.emulator?.id == id }
    }

    var body: some View {
        Group {
            if emulators.isEmpty {
                ContentUnavailableView(
                    "No emulators",
                    systemImage: "gearshape.2",
                    description: Text("Add an emulator in the Emulators tab first, then choose folders here.")
                )
            } else {
                Form {
                    Section {
                        Picker("Emulator", selection: Binding(
                            get: { effectiveEmulatorID },
                            set: { selectedEmulatorID = $0 }
                        )) {
                            ForEach(emulators) { emu in
                                Text(emu.name).tag(emu.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Game folders for this emulator") {
                        if pathsForSelection.isEmpty {
                            Text("No folders yet. Use “Add folder…” to pick a directory to scan.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pathsForSelection) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.folderPath)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete(perform: deletePaths)
                        }

                        Button("Add folder…", systemImage: "folder.badge.plus") {
                            addFolder()
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Paths")
        .onAppear {
            if selectedEmulatorID == nil {
                selectedEmulatorID = emulators.first?.id
            } else if let id = selectedEmulatorID, !emulators.contains(where: { $0.id == id }) {
                selectedEmulatorID = emulators.first?.id
            }
        }
        .onChange(of: emulators.map(\.id)) { _, ids in
            if let id = selectedEmulatorID, !ids.contains(id) {
                selectedEmulatorID = emulators.first?.id
            }
        }
    }

    private func addFolder() {
        let emuID = effectiveEmulatorID
        guard let emulator = emulators.first(where: { $0.id == emuID }) else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let path = (url.path as NSString).standardizingPath
            DispatchQueue.main.async {
                let desc = FetchDescriptor<GameFolderPath>()
                let existing = (try? modelContext.fetch(desc)) ?? []
                if existing.contains(where: { ($0.folderPath as NSString).standardizingPath == path && $0.emulator?.id == emuID }) {
                    return
                }
                let nextOrder = existing.filter { $0.emulator?.id == emuID }.map(\.sortOrder).max().map { $0 + 1 } ?? 0
                let entry = GameFolderPath(
                    folderPath: path,
                    emulator: emulator,
                    sortOrder: nextOrder
                )
                modelContext.insert(entry)
            }
        }
    }

    private func deletePaths(at offsets: IndexSet) {
        let toDelete = offsets.map { pathsForSelection[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
    }
}
