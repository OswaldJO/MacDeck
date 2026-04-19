import SwiftData
import SwiftUI

struct EmulatorsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]

    @State private var name: String = ""
    @State private var executablePath: String = ""
    @State private var argumentTemplate: String = "\"{ImagePath}\""
    /// Filters the Playnite-derived profile list shown under Display name.
    @State private var librarySearch: String = ""
    /// Sheet uses a stable `Identifiable` token (not a managed object) to avoid SwiftData invalidation crashes.
    @State private var editingEmulator: EditingEmulatorToken?

    private var filteredLibrary: [BuiltinEmulatorProfileRecord] {
        BuiltinEmulatorCatalogCache.profiles.filteredForSearch(librarySearch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add emulator") {
                    TextField("Display name", text: $name)

                    TextField("Search emulator library…", text: $librarySearch)
                        .textFieldStyle(.roundedBorder)

                    if librarySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Type an emulator or profile name to filter. Tap a row to set display name and launch arguments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if filteredLibrary.isEmpty {
                            Text("No matches. Try another name (e.g. PCSX2, RetroArch, Dolphin).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(filteredLibrary) { record in
                                        Button {
                                            applyCatalogProfile(record)
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(record.displayTitle)
                                                        .font(.body.weight(.medium))
                                                        .foregroundStyle(.primary)
                                                        .multilineTextAlignment(.leading)
                                                    Text(record.startupArguments)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                }
                                                Spacer(minLength: 8)
                                                if record.needsMacPathReview {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(.orange)
                                                        .help("May need macOS path tweaks (e.g. RetroArch core .dylib).")
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 240)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        }
                    }

                    TextField("Path to .app or executable", text: $executablePath)
                    TextField("Launch arguments (Playnite: {ImagePath} for game file; {ROM} and {rom} also work)", text: $argumentTemplate)
                    Button("Add") { addEmulator() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || executablePath.isEmpty)
                }

                Section("Configured") {
                    ForEach(emulators) { emu in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(emu.name).font(.headline)
                                Text(emu.executablePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(emu.launchArgumentTemplate)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 2) {
                                Button {
                                    editingEmulator = EditingEmulatorToken(emulatorID: emu.id)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Edit this emulator")

                                Button(role: .destructive) {
                                    deleteEmulator(emu)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this emulator")
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Edit…") {
                                editingEmulator = EditingEmulatorToken(emulatorID: emu.id)
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteEmulator(emu)
                            }
                        }
                    }
                    .onDelete(perform: deleteEmulators)
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("Emulators")
        }
        .frame(minWidth: 480, minHeight: 360)
        .sheet(item: $editingEmulator) { token in
            EditEmulatorSheet(emulatorID: token.emulatorID) {
                editingEmulator = nil
            }
        }
    }

    private func applyCatalogProfile(_ record: BuiltinEmulatorProfileRecord) {
        name = record.displayTitle
        argumentTemplate = record.startupArguments
        librarySearch = ""
    }

    private func addEmulator() {
        let profile = EmulatorProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            executablePath: executablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            launchArgumentTemplate: argumentTemplate,
            sortOrder: emulators.count
        )
        modelContext.insert(profile)
        name = ""
        executablePath = ""
        argumentTemplate = "\"{ImagePath}\""
        librarySearch = ""
    }

    private func deleteEmulator(_ emu: EmulatorProfile) {
        if editingEmulator?.emulatorID == emu.id {
            editingEmulator = nil
        }
        modelContext.delete(emu)
    }

    private func deleteEmulators(at offsets: IndexSet) {
        for index in offsets {
            let emu = emulators[index]
            if editingEmulator?.emulatorID == emu.id {
                editingEmulator = nil
            }
            modelContext.delete(emu)
        }
    }
}

private struct EditingEmulatorToken: Identifiable {
    let emulatorID: UUID
    var id: UUID { emulatorID }
}

// MARK: - Edit sheet

private struct EditEmulatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let emulatorID: UUID
    var onFinished: () -> Void

    @State private var name: String = ""
    @State private var executablePath: String = ""
    @State private var launchArgumentTemplate: String = ""
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    ContentUnavailableView(
                        "Emulator unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This entry was removed or the library was reset. Close and try again.")
                    )
                } else {
                    Form {
                        Section("Emulator") {
                            TextField("Display name", text: $name)
                            TextField("Path to .app or executable", text: $executablePath)
                            TextField("Launch arguments (Playnite: {ImagePath}; {ROM} and {rom} also work)", text: $launchArgumentTemplate)
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                }
            }
            .navigationTitle("Edit emulator")
            .task(id: emulatorID) {
                await loadFromStore()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onFinished()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveIfPossible()
                    }
                    .disabled(loadFailed || name.trimmingCharacters(in: .whitespaces).isEmpty
                        || executablePath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 260)
    }

    @MainActor
    private func loadFromStore() async {
        let uid = emulatorID
        let descriptor = FetchDescriptor<EmulatorProfile>(
            predicate: #Predicate { $0.id == uid }
        )
        guard let profile = try? modelContext.fetch(descriptor).first else {
            loadFailed = true
            return
        }
        name = profile.name
        executablePath = profile.executablePath
        launchArgumentTemplate = profile.launchArgumentTemplate
        loadFailed = false
    }

    @MainActor
    private func saveIfPossible() {
        let uid = emulatorID
        let descriptor = FetchDescriptor<EmulatorProfile>(
            predicate: #Predicate { $0.id == uid }
        )
        guard let profile = try? modelContext.fetch(descriptor).first else {
            loadFailed = true
            return
        }
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.launchArgumentTemplate = launchArgumentTemplate
        try? modelContext.save()
        onFinished()
        dismiss()
    }
}
