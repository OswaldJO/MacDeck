import SwiftData
import SwiftUI

private enum MainSection: Hashable {
    case library
    case emulators
    case paths
    case streaming
    case controllerMapping
}

private enum LibrarySidebarSelection: Hashable {
    case all
    case emulator(UUID)
}

public struct RootView: View {
    public init() {}

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.sortOrder) private var emulators: [EmulatorProfile]
    @Query(sort: \LibraryGame.sortOrder) private var games: [LibraryGame]

    @State private var sidebarSelection: LibrarySidebarSelection = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var section: MainSection = .library
    @State private var scanFeedback: String?
    @State private var confirmClearAllGames = false
    @State private var clearEmulatorGamesID: UUID?
    @State private var showStoredDataInspector = false
    @State private var showMetadataSettings = false

    private var filteredGames: [LibraryGame] {
        switch sidebarSelection {
        case .all:
            return games
        case .emulator(let id):
            return games.filter { $0.emulator?.id == id }
        }
    }

    public var body: some View {
        TabView(selection: $section) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: $sidebarSelection) {
                    Section("Library") {
                        Text("All")
                            .tag(LibrarySidebarSelection.all)
                            .contextMenu {
                                Button("Clear All Games…", systemImage: "trash", role: .destructive) {
                                    confirmClearAllGames = true
                                }
                            }
                        ForEach(emulators, id: \.id) { emu in
                            Text(emu.name)
                                .tag(LibrarySidebarSelection.emulator(emu.id))
                                .contextMenu {
                                    Button("Clear Games for “\(emu.name)”…", systemImage: "trash", role: .destructive) {
                                        clearEmulatorGamesID = emu.id
                                    }
                                }
                        }
                    }
                }
                .navigationTitle("Games")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            addGamePlaceholder()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add Game")

                        Button {
                            performScan()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help("Scan Paths")

                        Button {
                            showStoredDataInspector = true
                        } label: {
                            Image(systemName: "cylinder.split.1x2")
                        }
                        .help("Inspect SwiftData store and file path")

                        Button {
                            showMetadataSettings = true
                        } label: {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        .help("Metadata (IGDB) credentials")
                    }
                }
                .alert("Scan Paths", isPresented: Binding(
                    get: { scanFeedback != nil },
                    set: { if !$0 { scanFeedback = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(scanFeedback ?? "")
                }
                .confirmationDialog(
                    "Clear entire library?",
                    isPresented: $confirmClearAllGames,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Games", role: .destructive) {
                        removeEveryGameFromLibrary()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every game entry is removed. Your folders on disk are unchanged—use Scan Paths to import again.")
                }
                .confirmationDialog(
                    "Clear games for this emulator?",
                    isPresented: Binding(
                        get: { clearEmulatorGamesID != nil },
                        set: { if !$0 { clearEmulatorGamesID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Clear Games", role: .destructive) {
                        if let id = clearEmulatorGamesID {
                            removeAllGames(forEmulatorID: id)
                        }
                        clearEmulatorGamesID = nil
                    }
                    Button("Cancel", role: .cancel) {
                        clearEmulatorGamesID = nil
                    }
                } message: {
                    if let id = clearEmulatorGamesID,
                       let emu = emulators.first(where: { $0.id == id }) {
                        Text("Removes all library entries for “\(emu.name)”. Scan Paths can add them again.")
                    }
                }
            } detail: {
                LibraryGamesGridView(
                    games: filteredGames,
                    onPlay: { play($0) },
                    onDelete: { deleteGame($0) }
                )
            }
            .navigationSplitViewStyle(.balanced)
            .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            .tag(MainSection.library)

            EmulatorsView()
                .tabItem { Label("Emulators", systemImage: "gearshape.2") }
                .tag(MainSection.emulators)

            PathsView()
                .tabItem { Label("Paths", systemImage: "folder") }
                .tag(MainSection.paths)

            StreamingView()
                .tabItem { Label("Streaming", systemImage: "dot.radiowaves.left.and.right") }
                .tag(MainSection.streaming)

            ControllerMappingView()
                .tabItem { Label("Controllers", systemImage: "gamecontroller") }
                .tag(MainSection.controllerMapping)
        }
        .onChange(of: emulators.map(\.id)) { _, ids in
            if case .emulator(let selectedId) = sidebarSelection, !ids.contains(selectedId) {
                sidebarSelection = .all
            }
        }
        .task {
            MetadataBackgroundFetcher.shared.startIfNeeded(container: modelContext.container)
        }
        .sheet(isPresented: $showStoredDataInspector) {
            StoredDataInspectorView()
        }
        .sheet(isPresented: $showMetadataSettings) {
            IGDBSettingsSheet()
        }
        .onChange(of: showMetadataSettings) { _, isShowing in
            if !isShowing {
                MetadataBackgroundFetcher.shared.scheduleExtraPass(container: modelContext.container)
            }
        }
    }

    private func performScan() {
        do {
            let added = try GamePathScanner.scan(modelContext: modelContext)
            scanFeedback =
                added == 0
                ? "No new games found. Add folders in Paths or check that files use supported extensions."
                : "Added \(added) game(s) to the library."
            if added > 0 {
                MetadataBackgroundFetcher.shared.scheduleExtraPass(container: modelContext.container)
            }
        } catch {
            scanFeedback = "Scan failed: \(error.localizedDescription)"
        }
    }

    private func play(_ game: LibraryGame) {
        let gameID = game.id
        var descriptor = FetchDescriptor<LibraryGame>(
            predicate: #Predicate { $0.id == gameID }
        )
        descriptor.fetchLimit = 1
        guard let fresh = try? modelContext.fetch(descriptor).first else {
            NSLog("Play: library game no longer in store (id: \(gameID))")
            return
        }
        do {
            try GameLauncher.launch(game: fresh)
            fresh.lastPlayed = Date()
            try modelContext.save()
        } catch {
            NSLog("%@", error.localizedDescription)
        }
    }

    private func deleteGame(_ game: LibraryGame) {
        modelContext.delete(game)
    }

    private func removeEveryGameFromLibrary() {
        let snapshot = games
        for game in snapshot {
            modelContext.delete(game)
        }
        try? modelContext.save()
    }

    private func removeAllGames(forEmulatorID emulatorID: UUID) {
        let snapshot = games.filter { $0.emulator?.id == emulatorID }
        for game in snapshot {
            modelContext.delete(game)
        }
        try? modelContext.save()
    }

    private func addGamePlaceholder() {
        let emu = emulators.first
        let game = LibraryGame(
            title: "Sample Game",
            romPath: "/path/to/rom",
            emulator: emu,
            sortOrder: games.count
        )
        modelContext.insert(game)
    }
}

// MARK: - Library grid (main column)

private struct LibraryGamesGridView: View {
    let games: [LibraryGame]
    let onPlay: (LibraryGame) -> Void
    let onDelete: (LibraryGame) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        Group {
            if games.isEmpty {
                ContentUnavailableView(
                    "No games",
                    systemImage: "gamecontroller",
                    description: Text("Use Paths and Scan Paths to import games, or add a game manually.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(games) { game in
                            GameLibraryTile(game: game, onPlay: { onPlay(game) })
                                .contextMenu {
                                    Button("Play", systemImage: "play.fill") { onPlay(game) }
                                    Divider()
                                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                        onDelete(game)
                                    }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GameLibraryTile: View {
    let game: LibraryGame
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                CoverThumbnail(urlString: game.coverImageURLString)
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }

                Text(game.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play \(game.title)")
    }
}

// MARK: - Cover art

private struct CoverThumbnail: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = Self.resolvedImageURL(from: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.secondary.opacity(0.2)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private static func resolvedImageURL(from string: String) -> URL? {
        let normalized = string.hasPrefix("//") ? "https:" + string : string
        guard let url = URL(string: normalized),
              url.isFileURL || url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

extension LibraryGame: Hashable {
    public static func == (lhs: LibraryGame, rhs: LibraryGame) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [EmulatorProfile.self, LibraryGame.self, GameFolderPath.self], inMemory: true)
}
