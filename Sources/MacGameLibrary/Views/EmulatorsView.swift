import SwiftData
import SwiftUI

/// One selectable row in the bundled catalog or a user-added “Default Launch Arguments” preset.
private enum LibraryProfileRow: Identifiable {
    case builtin(BuiltinEmulatorProfileRecord)
    case custom(CustomEmulatorLibraryEntry)

    var id: String {
        switch self {
        case .builtin(let r): return "builtin-\(r.catalogId)"
        case .custom(let e): return "custom-\(e.id.uuidString)"
        }
    }

    var sortTitle: String {
        switch self {
        case .builtin(let r): return r.displayTitle
        case .custom(let e): return e.displayTitle
        }
    }
}

struct EmulatorsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]

    @State private var name: String = ""
    @State private var executablePath: String = ""
    @State private var argumentTemplate: String = "\"{ImagePath}\""
    /// Filter for the “Add emulator” catalog list only (independent from Default Launch Arguments).
    @State private var addEmulatorLibrarySearch: String = ""
    /// Filter for the Default Launch Arguments list.
    @State private var defaultLaunchArgumentsSearch: String = ""
    /// Bumped when bundled-catalog overrides change.
    @State private var catalogOverridesVersion: Int = 0
    /// Bumped when custom library entries change.
    @State private var customLibraryVersion: Int = 0
    /// `catalogId` of the bundled row being edited (list hidden while set).
    @State private var editingCatalogRecordId: Int?
    @State private var emulatorsLibraryEditDraft: String = ""
    @State private var editingCustomEntryId: UUID?
    @State private var customEditDraftTitle: String = ""
    @State private var customEditDraftArgs: String = ""
    @State private var showAddCustomLibraryEntrySheet = false
    /// Sheet uses a stable `Identifiable` token (not a managed object) to avoid SwiftData invalidation crashes.
    @State private var editingEmulator: EditingEmulatorToken?

    private func filteredCustomEntries(search: String) -> [CustomEmulatorLibraryEntry] {
        let all = CustomEmulatorLibraryStore.allEntries()
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return all.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }
        return all.filter { entry in
            entry.displayTitle.lowercased().contains(q) || entry.startupArguments.lowercased().contains(q)
        }
        .sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private func mergedLibraryRows(search: String) -> [LibraryProfileRow] {
        let builtins = BuiltinEmulatorCatalogCache.profiles
            .matchingCatalogSearch(search)
            .sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        let customs = filteredCustomEntries(search: search)
        let rows = customs.map { LibraryProfileRow.custom($0) } + builtins.map { LibraryProfileRow.builtin($0) }
        return rows.sorted {
            $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending
        }
    }

    private var addEmulatorMergedRows: [LibraryProfileRow] {
        mergedLibraryRows(search: addEmulatorLibrarySearch)
    }

    private var defaultLaunchArgumentsMergedRows: [LibraryProfileRow] {
        mergedLibraryRows(search: defaultLaunchArgumentsSearch)
    }

    private func subtitle(for row: LibraryProfileRow) -> String {
        switch row {
        case .builtin(let r):
            return CatalogLaunchArgumentOverrides.effectiveStartupArguments(for: r)
        case .custom(let e):
            return e.startupArguments
        }
    }

    private func macPathWarning(for row: LibraryProfileRow) -> Bool {
        switch row {
        case .builtin(let r):
            return r.needsMacPathReview
        case .custom(let e):
            let a = e.startupArguments
            if a.contains(".dll") { return true }
            if a.lowercased().contains("libretro") { return true }
            if a.contains("\\cores\\") || a.contains(".\\cores") { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add emulator") {
                    TextField("Display name", text: $name)

                    TextField("Search Emulators Library", text: $addEmulatorLibrarySearch)
                        .textFieldStyle(.roundedBorder)

                    if addEmulatorLibrarySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Type an emulator or profile name to filter. Tap a row to set display name and launch arguments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if addEmulatorMergedRows.isEmpty {
                            Text("No matches. Try another name (e.g. PCSX2, RetroArch, Dolphin).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(addEmulatorMergedRows) { row in
                                        Button {
                                            applyLibraryProfileRow(row)
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(row.sortTitle)
                                                        .font(.body.weight(.medium))
                                                        .foregroundStyle(.primary)
                                                        .multilineTextAlignment(.leading)
                                                    Text(subtitle(for: row))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                        .id("\(row.id)-\(catalogOverridesVersion)-\(customLibraryVersion)")
                                                }
                                                Spacer(minLength: 8)
                                                if macPathWarning(for: row) {
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

                Section("Default Launch Arguments") {
                    if let catalogId = editingCatalogRecordId,
                       let record = BuiltinEmulatorCatalogCache.profiles.first(where: { $0.catalogId == catalogId }) {
                        EmulatorsLibraryEditPane(
                            record: record,
                            draftArguments: $emulatorsLibraryEditDraft,
                            onCancel: {
                                editingCatalogRecordId = nil
                            },
                            onSave: {
                                CatalogLaunchArgumentOverrides.setEffectiveStartupArguments(
                                    emulatorsLibraryEditDraft,
                                    catalogId: catalogId
                                )
                                catalogOverridesVersion += 1
                                editingCatalogRecordId = nil
                            }
                        )
                    } else if let customId = editingCustomEntryId,
                              CustomEmulatorLibraryStore.allEntries().contains(where: { $0.id == customId }) {
                        CustomLibraryEntryEditPane(
                            draftTitle: $customEditDraftTitle,
                            draftArguments: $customEditDraftArgs,
                            onCancel: {
                                editingCustomEntryId = nil
                            },
                            onSave: {
                                CustomEmulatorLibraryStore.update(
                                    id: customId,
                                    displayTitle: customEditDraftTitle,
                                    startupArguments: customEditDraftArgs
                                )
                                customLibraryVersion += 1
                                editingCustomEntryId = nil
                            },
                            onDelete: {
                                CustomEmulatorLibraryStore.remove(id: customId)
                                customLibraryVersion += 1
                                editingCustomEntryId = nil
                            }
                        )
                    } else {
                        Button {
                            showAddCustomLibraryEntrySheet = true
                        } label: {
                            Label("Add emulator", systemImage: "plus")
                        }

                        TextField("Search Default Launch Arguments", text: $defaultLaunchArgumentsSearch)
                            .textFieldStyle(.roundedBorder)

                        if defaultLaunchArgumentsMergedRows.isEmpty {
                            Text("No matches. Try another name (e.g. PCSX2, RetroArch, Dolphin).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(defaultLaunchArgumentsMergedRows) { row in
                                        Button {
                                            switch row {
                                            case .builtin(let record):
                                                editingCustomEntryId = nil
                                                editingCatalogRecordId = record.catalogId
                                                emulatorsLibraryEditDraft = CatalogLaunchArgumentOverrides
                                                    .effectiveStartupArguments(for: record)
                                            case .custom(let entry):
                                                editingCatalogRecordId = nil
                                                editingCustomEntryId = entry.id
                                                customEditDraftTitle = entry.displayTitle
                                                customEditDraftArgs = entry.startupArguments
                                            }
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(row.sortTitle)
                                                        .font(.body.weight(.medium))
                                                        .foregroundStyle(.primary)
                                                        .multilineTextAlignment(.leading)
                                                    Text(subtitle(for: row))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                        .id("\(row.id)-\(catalogOverridesVersion)-\(customLibraryVersion)")
                                                }
                                                Spacer(minLength: 8)
                                                if macPathWarning(for: row) {
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
                            .frame(maxHeight: 320)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        }
                    }
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
        .sheet(isPresented: $showAddCustomLibraryEntrySheet) {
            AddCustomEmulatorLibraryEntrySheet { displayTitle, startupArguments in
                CustomEmulatorLibraryStore.add(displayTitle: displayTitle, startupArguments: startupArguments)
                customLibraryVersion += 1
            }
        }
    }

    private func applyLibraryProfileRow(_ row: LibraryProfileRow) {
        switch row {
        case .builtin(let record):
            applyCatalogProfile(record)
        case .custom(let entry):
            name = entry.displayTitle
            argumentTemplate = entry.startupArguments
            addEmulatorLibrarySearch = ""
        }
    }

    private func applyCatalogProfile(_ record: BuiltinEmulatorProfileRecord) {
        name = record.displayTitle
        argumentTemplate = CatalogLaunchArgumentOverrides.effectiveStartupArguments(for: record)
        addEmulatorLibrarySearch = ""
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
        addEmulatorLibrarySearch = ""
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

// MARK: - Default Launch Arguments (custom entry editor)

private struct CustomLibraryEntryEditPane: View {
    @Binding var draftTitle: String
    @Binding var draftArguments: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom preset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Display name", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            Text("Default launch arguments")
                .font(.subheadline.weight(.semibold))
            Text("Used when you choose this preset under “Add emulator”. Use `{ImagePath}` for the game file; `{ROM}` and `{rom}` also work.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Launch arguments", text: $draftArguments, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...12)

            HStack {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draftArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddCustomEmulatorLibraryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayTitle: String = ""
    @State private var startupArguments: String = "\"{ImagePath}\""
    let onCommit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayTitle)
                    TextField("Default launch arguments", text: $startupArguments, axis: .vertical)
                        .lineLimit(4...12)
                } footer: {
                    Text("This preset appears in both lists here and under “Add emulator”. Use `{ImagePath}` for the game file.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("Add emulator")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let a = startupArguments.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCommit(t, a)
                        dismiss()
                    }
                    .disabled(
                        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || startupArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}

// MARK: - Bundled catalog defaults editor

private struct EmulatorsLibraryEditPane: View {
    let record: BuiltinEmulatorProfileRecord
    @Binding var draftArguments: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.displayTitle)
                .font(.title3.weight(.semibold))

            Text("Catalog default (from bundled library)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(record.startupArguments)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Default launch arguments")
                .font(.subheadline.weight(.semibold))
            Text("This text is used when you choose this profile under “Add emulator”. Use `{ImagePath}` for the game file; `{ROM}` and `{rom}` also work.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Launch arguments", text: $draftArguments, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...12)

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
