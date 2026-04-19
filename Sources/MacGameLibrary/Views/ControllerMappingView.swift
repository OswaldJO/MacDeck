import CoreGraphics
import SwiftUI

private enum ActionTargetKind: String, CaseIterable, Identifiable {
    case keyboard
    case numpadDigit
    case mouse
    case scroll
    case trackpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keyboard: return "Keyboard key"
        case .numpadDigit: return "Numpad digit (0–9)"
        case .mouse: return "Mouse button"
        case .scroll: return "Mouse wheel (vertical)"
        case .trackpad: return "Trackpad scroll (vertical)"
        }
    }
}

struct ControllerMappingView: View {
    @State private var store = ControllerMappingStore()
    @State private var controllers = ConnectedControllersObserver()
    @State private var showAddBinding = false
    @State private var showNewProfileSheet = false
    @State private var newProfileName = ""
    @State private var profileToDelete: UUID?

    var body: some View {
        NavigationStack {
            Form {
                accessibilitySection
                controllersSection
                profileSection
                bindingsSection
            }
            .formStyle(.grouped)
            .navigationTitle("Controller mapping")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBinding = true
                    } label: {
                        Label("Add mapping", systemImage: "plus")
                    }
                    .disabled(store.selectedProfile == nil)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showAddBinding) {
            AddControllerBindingSheet(onSave: { binding in
                store.addBinding(binding)
                showAddBinding = false
            }, onCancel: {
                showAddBinding = false
            })
        }
        .sheet(isPresented: $showNewProfileSheet) {
            NavigationStack {
                Form {
                    TextField("Profile name", text: $newProfileName)
                }
                .formStyle(.grouped)
                .navigationTitle("New profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showNewProfileSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.addProfile(named: name.isEmpty ? "Profile \(store.profiles.count + 1)" : name)
                            newProfileName = ""
                            showNewProfileSheet = false
                        }
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 160)
        }
        .confirmationDialog(
            "Delete this profile and its mappings?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    store.deleteProfile(id: id)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        }
    }

    private var accessibilitySection: some View {
        Section {
            Text(
                "Synthetic keyboard, numpad, mouse, and scroll events need **Accessibility** permission (System Settings → Privacy & Security → Accessibility) for this app. Without it, “Test action” may not affect other apps."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } header: {
            Text("Permissions")
        }
    }

    private var controllersSection: some View {
        Section("Connected controllers") {
            if controllers.controllers.isEmpty {
                Text("None detected. Connect a game controller and press Refresh, or pair a Bluetooth controller in System Settings.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(controllers.controllers.enumerated()), id: \.offset) { _, c in
                    LabeledContent(controllers.displayName(for: c)) {
                        Text(c.vendorName ?? "Game controller")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Refresh list", systemImage: "arrow.clockwise") {
                controllers.refresh()
            }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            if store.profiles.isEmpty {
                Text("No profiles")
            } else {
                Picker("Active profile", selection: Binding(
                    get: { store.selectedProfileID },
                    set: { store.selectProfile(id: $0) }
                )) {
                    ForEach(store.profiles) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .pickerStyle(.menu)

                Button("New profile…") {
                    newProfileName = ""
                    showNewProfileSheet = true
                }

                if store.profiles.count > 1, let id = store.selectedProfileID {
                    Button("Delete profile…", role: .destructive) {
                        profileToDelete = id
                    }
                }
            }
        }
    }

    private var bindingsSection: some View {
        Section("Mappings") {
            if let profile = store.selectedProfile {
                if profile.bindings.isEmpty {
                    Text("No bindings yet. Use Add mapping to assign a controller button to a key or mouse action.")
                        .foregroundStyle(.secondary)
                } else {
                    let sorted = profile.bindings.sorted(by: { $0.sourceLabel < $1.sourceLabel })
                    List {
                        ForEach(sorted) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(b.sourceLabel)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Button("Test action") {
                                        SyntheticInputPlayback.perform(b.action)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                Text(b.action.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    store.removeBinding(id: b.id)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                store.removeBinding(id: sorted[i].id)
                            }
                        }
                    }
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }
}

// MARK: - Add binding sheet

private struct AddControllerBindingSheet: View {
    let onSave: (ControllerBinding) -> Void
    let onCancel: () -> Void

    @State private var sourceID: String = GamepadElementCatalog.extendedGamepad.first?.elementID ?? "buttonA"
    @State private var targetKind: ActionTargetKind = .keyboard
    @State private var keyboardPick: CGKeyCode = VirtualKeyCatalog.common[0].virtualKeyCode
    @State private var numpadDigit = 0
    @State private var mouseRaw: UInt32 = 0
    @State private var scrollSteps = 3
    @State private var scrollSign = 1
    @State private var trackpadSteps = 3
    @State private var trackpadSign = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Controller input") {
                    Picker("Physical control", selection: $sourceID) {
                        ForEach(GamepadElementCatalog.extendedGamepad) { opt in
                            Text(opt.label).tag(opt.elementID)
                        }
                    }
                }

                Section("Maps to") {
                    Picker("Target type", selection: $targetKind) {
                        ForEach(ActionTargetKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }

                    switch targetKind {
                    case .keyboard:
                        Picker("Key", selection: $keyboardPick) {
                            ForEach(VirtualKeyCatalog.allKeyboardAndNumpad) { opt in
                                Text(opt.label).tag(opt.virtualKeyCode)
                            }
                        }
                    case .numpadDigit:
                        Picker("Digit", selection: $numpadDigit) {
                            ForEach(0 ... 9, id: \.self) { d in
                                Text("\(d)").tag(d)
                            }
                        }
                    case .mouse:
                        Picker("Button", selection: $mouseRaw) {
                            Text("Left").tag(UInt32(0))
                            Text("Right").tag(UInt32(1))
                            Text("Middle").tag(UInt32(2))
                        }
                    case .scroll:
                        Stepper("Steps (×\(scrollSign > 0 ? scrollSteps : -scrollSteps))", value: $scrollSteps, in: 1 ... 20)
                        Picker("Direction", selection: $scrollSign) {
                            Text("Scroll up").tag(1)
                            Text("Scroll down").tag(-1)
                        }
                    case .trackpad:
                        Stepper("Steps (×\(trackpadSign > 0 ? trackpadSteps : -trackpadSteps))", value: $trackpadSteps, in: 1 ... 20)
                        Picker("Direction", selection: $trackpadSign) {
                            Text("Scroll up").tag(1)
                            Text("Scroll down").tag(-1)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let opt = GamepadElementCatalog.extendedGamepad.first(where: { $0.elementID == sourceID }) else { return }
                        let action: MappedAction
                        switch targetKind {
                        case .keyboard:
                            action = .keyboardKey(keyboardPick)
                        case .numpadDigit:
                            action = .numpadDigit(numpadDigit)
                        case .mouse:
                            action = .mouseButton(mouseRaw)
                        case .scroll:
                            action = .scrollVertical(scrollSign * scrollSteps)
                        case .trackpad:
                            action = .trackpadScrollVertical(trackpadSign * trackpadSteps)
                        }
                        onSave(ControllerBinding(sourceElementID: opt.elementID, sourceLabel: opt.label, action: action))
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 380)
    }
}

#Preview {
    ControllerMappingView()
}
