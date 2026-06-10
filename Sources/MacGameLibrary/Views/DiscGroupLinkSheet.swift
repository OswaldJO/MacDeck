import SwiftData
import SwiftUI

struct DiscGroupLinkSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let anchorGame: LibraryGame
    let allGames: [LibraryGame]

    @State private var selectedIDs: Set<UUID> = []

    private var suggested: [LibraryGame] {
        DiscGroupService.suggestedLinkCandidates(for: anchorGame, among: allGames)
    }

    private var alreadyLinked: [LibraryGame] {
        DiscGroupService.linkedGames(for: anchorGame, context: modelContext)
    }

    private var selectableCandidates: [LibraryGame] {
        let linkedIDs = Set(alreadyLinked.map(\.id))
        var seen = linkedIDs
        seen.insert(anchorGame.id)

        var output: [LibraryGame] = []
        for game in suggested where !seen.contains(game.id) {
            output.append(game)
            seen.insert(game.id)
        }

        let anchorEmulator = anchorGame.emulatorUUID
        let anchorBase = DiscGroupService.discBaseTitle(for: anchorGame)
        for game in allGames.sorted(by: { $0.libraryListTitle.localizedCaseInsensitiveCompare($1.libraryListTitle) == .orderedAscending }) {
            guard !seen.contains(game.id) else { continue }
            let sameEmulator = anchorEmulator == nil || game.emulatorUUID == anchorEmulator
            let similarTitle = !anchorBase.isEmpty && DiscGroupService.discBaseTitle(for: game) == anchorBase
            if sameEmulator || similarTitle {
                output.append(game)
                seen.insert(game.id)
            }
        }
        return output
    }

    var body: some View {
        NavigationStack {
            Form {
                if !alreadyLinked.isEmpty {
                    Section("Currently linked") {
                        ForEach(alreadyLinked) { linked in
                            linkedRow(linked, isAnchor: linked.id == anchorGame.id)
                        }
                    }
                }

                Section {
                    Text("Select the other discs for “\(DiscGroupService.discBaseTitle(for: anchorGame).isEmpty ? anchorGame.libraryListTitle : DiscGroupService.discBaseTitle(for: anchorGame))”. Cover art and ScreenScraper metadata will stay in sync across the set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectableCandidates.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No candidates",
                            systemImage: "opticaldisc",
                            description: Text("Add the other disc files to your library first, then link them here.")
                        )
                    }
                } else {
                    Section(suggested.isEmpty ? "Library games" : "Suggested matches") {
                        ForEach(selectableCandidates) { candidate in
                            Toggle(isOn: binding(for: candidate.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.libraryListTitle)
                                    Text(URL(fileURLWithPath: candidate.romPath).lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Link Multi-Disc Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") { linkSelected() }
                        .disabled(selectedIDs.isEmpty)
                }
            }
            .onAppear {
                selectedIDs = Set(suggested.map(\.id))
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private func linkedRow(_ game: LibraryGame, isAnchor: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.libraryListTitle)
                Text(URL(fileURLWithPath: game.romPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let label = DiscGroupService.discLabel(for: game) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if isAnchor {
                Text("This disc")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in
                if isOn {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }

    private func linkSelected() {
        let selected = selectableCandidates.filter { selectedIDs.contains($0.id) }
        var toLink = alreadyLinked
        if !toLink.contains(where: { $0.id == anchorGame.id }) {
            toLink.append(anchorGame)
        }
        toLink.append(contentsOf: selected)
        DiscGroupService.link(toLink, context: modelContext)
        dismiss()
    }
}
