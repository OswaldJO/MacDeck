import SwiftData
import SwiftUI

struct EmulatorsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]

    @State private var name: String = ""
    @State private var executablePath: String = ""
    @State private var argumentTemplate: String = "\"{rom}\""

    var body: some View {
        Form {
            Section("Add emulator") {
                TextField("Display name", text: $name)
                TextField("Path to .app or executable", text: $executablePath)
                TextField("Launch arguments (use {rom} for game file)", text: $argumentTemplate)
                Button("Add") { addEmulator() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || executablePath.isEmpty)
            }

            Section("Configured") {
                ForEach(emulators) { emu in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(emu.name).font(.headline)
                        Text(emu.executablePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(emu.launchArgumentTemplate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteEmulators)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Emulators")
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
    }

    private func deleteEmulators(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(emulators[index])
        }
    }
}
