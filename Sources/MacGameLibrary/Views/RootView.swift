import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @Query(sort: [SortDescriptor(\EmulatorProfile.name, comparator: .localizedStandard)]) private var emulators: [EmulatorProfile]
    @Query(sort: \LibraryGame.sortOrder) private var games: [LibraryGame]

    @State private var sidebarSelection: LibrarySidebarSelection = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var section: MainSection = .library
    @State private var scanFeedback: String?
    @State private var confirmClearAllGames = false
    @State private var clearEmulatorGamesID: UUID?
    /// Game card showing play / info overlay.
    @State private var actionOverlayGameID: UUID?
    /// Game open in the trailing inspector column.
    @State private var inspectorGameID: UUID?

    private var filteredGames: [LibraryGame] {
        switch sidebarSelection {
        case .all:
            return games
        case .emulator(let id):
            return games.filter { $0.emulator?.id == id }
        }
    }

    @ViewBuilder
    private var libraryDetailContent: some View {
        HStack(spacing: 0) {
            LibraryGamesGridView(
                games: filteredGames,
                actionOverlayGameID: $actionOverlayGameID,
                inspectorGameID: $inspectorGameID,
                onPlay: { play($0) },
                onDelete: { deleteGame($0) }
            )
            .frame(minWidth: 240)
            .layoutPriority(1)

            if let id = inspectorGameID,
               let game = filteredGames.first(where: { $0.id == id }) {
                Divider()
                NavigationStack {
                    LibraryGameInspectorView(game: game) {
                        inspectorGameID = nil
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 520)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: inspectorGameID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            Label("Add Game", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }

                        Button {
                            performScan()
                        } label: {
                            Label("Scan Paths", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
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
                libraryDetailContent
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
        .onChange(of: filteredGames.map(\.id)) { _, ids in
            if let id = inspectorGameID, !ids.contains(id) {
                inspectorGameID = nil
            }
            if let id = actionOverlayGameID, !ids.contains(id) {
                actionOverlayGameID = nil
            }
        }
        .task {
            MetadataBackgroundFetcher.shared.startIfNeeded(container: modelContext.container)
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
    @Binding var actionOverlayGameID: UUID?
    @Binding var inspectorGameID: UUID?
    let onPlay: (LibraryGame) -> Void
    let onDelete: (LibraryGame) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: LibraryGridMetrics.cardWidth, maximum: LibraryGridMetrics.cardWidth), spacing: LibraryGridMetrics.horizontalSpacing, alignment: .top)
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: LibraryGridMetrics.verticalSpacing) {
                        ForEach(games) { game in
                            GameLibraryTile(
                                game: game,
                                showsActionOverlay: actionOverlayGameID == game.id,
                                onCardTap: {
                                    if actionOverlayGameID == game.id {
                                        actionOverlayGameID = nil
                                    } else {
                                        actionOverlayGameID = game.id
                                    }
                                },
                                onPlay: {
                                    actionOverlayGameID = nil
                                    onPlay(game)
                                },
                                onInfo: {
                                    actionOverlayGameID = nil
                                    inspectorGameID = game.id
                                }
                            )
                            .contextMenu {
                                Button("Play", systemImage: "play.fill") { onPlay(game) }
                                Button("Details…", systemImage: "info.circle") {
                                    inspectorGameID = game.id
                                }
                                Divider()
                                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                    onDelete(game)
                                }
                            }
                        }
                    }
                    .padding(LibraryGridMetrics.outerPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum LibraryGridMetrics {
    static let cardWidth: CGFloat = 160
    static let coverHeight: CGFloat = 214
    static let titleHeight: CGFloat = 52 // reserve up to ~3 lines so rows align
    static let horizontalSpacing: CGFloat = 16
    static let verticalSpacing: CGFloat = 20
    static let outerPadding: CGFloat = 20
}

private struct GameLibraryTile: View {
    let game: LibraryGame
    let showsActionOverlay: Bool
    let onCardTap: () -> Void
    let onPlay: () -> Void
    let onInfo: () -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                CoverThumbnail(urlString: game.coverImageURLString)
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(width: LibraryGridMetrics.cardWidth, height: LibraryGridMetrics.coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }

                Text(game.libraryListTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(width: LibraryGridMetrics.cardWidth, height: LibraryGridMetrics.titleHeight, alignment: .topLeading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onCardTap)

            if showsActionOverlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
                    .onTapGesture(perform: onCardTap)

                HStack(spacing: 28) {
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .help("Play")

                    Button {
                        onInfo()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 40))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Game details and cover")
                }
            }
        }
        .frame(width: LibraryGridMetrics.cardWidth, alignment: .leading)
        .help("Show actions for \(game.libraryListTitle)")
    }
}

// MARK: - Inspector (cover + display name)

private struct LibraryGameInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var game: LibraryGame
    var onDismiss: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Name in library", text: nameBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Text("Renames how this game appears here only. The file on disk is not renamed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("File") {
                    Text(URL(fileURLWithPath: game.romPath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Cover art") {
                HStack(alignment: .top, spacing: 16) {
                    CoverThumbnail(urlString: game.coverImageURLString)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("Choose Image…", systemImage: "photo") {
                            pickCoverImage()
                        }
                        if game.coverImageURLString != nil {
                            Button("Clear cover", systemImage: "xmark.circle", role: .destructive) {
                                game.coverImageURLString = nil
                                try? modelContext.save()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle(game.libraryListTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onDismiss()
                } label: {
                    Label("Done", systemImage: "sidebar.right")
                }
                .help("Hide game details")
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: {
                game.libraryDisplayName ?? game.title
            },
            set: { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    game.libraryDisplayName = nil
                } else if trimmed == game.title {
                    game.libraryDisplayName = nil
                } else {
                    game.libraryDisplayName = trimmed
                }
                try? modelContext.save()
            }
        )
    }

    private func pickCoverImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let path = (url.path as NSString).standardizingPath
            let fileURL = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                game.coverImageURLString = fileURL.absoluteString
                try? modelContext.save()
            }
        }
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
