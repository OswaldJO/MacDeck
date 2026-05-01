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
    case macGames
    case emulator(UUID)
    case screenScraper
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
    @State private var cleanupFeedback: String?
    @State private var metadataFeedback: String?
    @State private var confirmClearAllGames = false
    @State private var confirmClearMacGames = false
    @State private var showScreenScraperSettings = false
    @State private var clearEmulatorGamesID: UUID?
    /// Game card showing play / info overlay.
    @State private var actionOverlayGameID: UUID?
    /// Game open in the trailing inspector column.
    @State private var inspectorGameID: UUID?

    private var activeEmulatorIDs: Set<UUID> {
        Set(emulators.map(\.id))
    }

    private var visibleLibraryGames: [LibraryGame] {
        games.filter { game in
            guard let emulatorID = game.emulatorUUID else { return true }
            return activeEmulatorIDs.contains(emulatorID)
        }
    }

    private var filteredGames: [LibraryGame] {
        let sortedVisible = visibleLibraryGames.sorted {
            let lhs = $0.libraryListTitle
            let rhs = $1.libraryListTitle
            let cmp = lhs.localizedStandardCompare(rhs)
            if cmp == .orderedSame {
                return $0.sortOrder < $1.sortOrder
            }
            return cmp == .orderedAscending
        }
        switch sidebarSelection {
        case .all:
            return sortedVisible
        case .macGames:
            return sortedVisible.filter { $0.emulatorUUID == nil }
        case .emulator(let id):
            return sortedVisible.filter { $0.emulatorUUID == id }
        case .screenScraper:
            return []
        }
    }

    @ViewBuilder
    private var macGamesSidebarItem: some View {
        Text("Mac Games")
            .tag(LibrarySidebarSelection.macGames)
            .contextMenu {
                Button("Clear Mac Games…", systemImage: "trash", role: .destructive) {
                    confirmClearMacGames = true
                }
            }
    }

    @ViewBuilder
    private var libraryDetailContent: some View {
        switch sidebarSelection {
        case .screenScraper:
            ScreenScraperLibrarySettingsView(
                isConfigured: MetadataCredentials.isConfigured,
                onOpenCredentials: { showScreenScraperSettings = true },
                onScrapeNow: { runScreenScraperScrapeNow() }
            )
        case .all, .macGames, .emulator:
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
    }

    @ViewBuilder
    private var libraryTab: some View {
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
                    macGamesSidebarItem
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
                Section("Cover Art and Metadata") {
                    Text("Screen Scrapper")
                        .tag(LibrarySidebarSelection.screenScraper)
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        addManualMacGame()
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

                    Button {
                        importEpicInstalledGames()
                    } label: {
                        Label("Import Epic Installed Games", systemImage: "shippingbox")
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        showScreenScraperSettings = true
                    } label: {
                        Label("Metadata Settings", systemImage: "photo.on.rectangle.angled")
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
                "Clear Mac games?",
                isPresented: $confirmClearMacGames,
                titleVisibility: .visible
            ) {
                Button("Clear Mac Games", role: .destructive) {
                    removeAllMacGames()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes all standalone Mac game entries. Files on disk are unchanged.")
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
    }

    public var body: some View {
        TabView(selection: $section) {
            libraryTab

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
            let removed = removeOrphanedGamesFromLibrary()
            if removed > 0 {
                cleanupFeedback = "Removed \(removed) orphan game(s) from the library. These entries referenced missing emulators and could appear as ghost games."
            }
            MetadataBackgroundFetcher.shared.startIfNeeded(container: modelContext.container)
        }
        .alert("Library Cleanup", isPresented: Binding(
            get: { cleanupFeedback != nil },
            set: { if !$0 { cleanupFeedback = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanupFeedback ?? "")
        }
        .alert("Metadata", isPresented: Binding(
            get: { metadataFeedback != nil },
            set: { if !$0 { metadataFeedback = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(metadataFeedback ?? "")
        }
        .sheet(isPresented: $showScreenScraperSettings) {
            ScreenScraperSettingsSheet()
        }
    }

    private func runScreenScraperScrapeNow() {
        Task { @MainActor in
            let summary = await MetadataBackgroundFetcher.shared.scrapeAllNow(container: modelContext.container)
            metadataFeedback = "ScreenScraper processed \(summary.processed) game(s). Updated \(summary.updated) game(s)."
        }
    }

    private func performScan() {
        do {
            let summary = try GamePathScanner.scan(modelContext: modelContext)
            let epicSummary = try EpicInstalledGamesImporter.importInstalledGames(modelContext: modelContext)
            if summary.hasAnyChanges {
                var parts: [String] = []
                if summary.added > 0 {
                    parts.append("Added \(summary.added) game(s)")
                }
                if summary.reassigned > 0 {
                    parts.append("Re-linked \(summary.reassigned) existing game(s) to this emulator")
                }
                if summary.linkedCovers > 0 {
                    parts.append("Linked \(summary.linkedCovers) cover image(s)")
                }
                if epicSummary.added > 0 {
                    parts.append("Imported \(epicSummary.added) Epic game(s)")
                }
                if epicSummary.updated > 0 {
                    parts.append("Updated \(epicSummary.updated) Epic game(s)")
                }
                scanFeedback = parts.joined(separator: ". ") + "."
            } else if epicSummary.hasChanges {
                var parts: [String] = []
                if epicSummary.added > 0 {
                    parts.append("Imported \(epicSummary.added) Epic game(s)")
                }
                if epicSummary.updated > 0 {
                    parts.append("Updated \(epicSummary.updated) Epic game(s)")
                }
                scanFeedback = parts.joined(separator: ". ") + "."
            } else {
                scanFeedback = "No new games found. Add folders in Paths or check that files use supported extensions."
            }
            if summary.added > 0 || epicSummary.added > 0 {
                MetadataBackgroundFetcher.shared.scheduleExtraPass(container: modelContext.container)
            }
        } catch {
            scanFeedback = "Scan failed: \(error.localizedDescription)"
        }
    }

    private func importEpicInstalledGames() {
        do {
            let epicSummary = try EpicInstalledGamesImporter.importInstalledGames(modelContext: modelContext)
            if epicSummary.hasChanges {
                var parts: [String] = []
                if epicSummary.added > 0 {
                    parts.append("Imported \(epicSummary.added) Epic game(s)")
                }
                if epicSummary.updated > 0 {
                    parts.append("Updated \(epicSummary.updated) Epic game(s)")
                }
                scanFeedback = parts.joined(separator: ". ") + "."
                if epicSummary.added > 0 {
                    MetadataBackgroundFetcher.shared.scheduleExtraPass(container: modelContext.container)
                }
            } else {
                scanFeedback = "No installed Epic games found to import."
            }
        } catch {
            scanFeedback = "Epic import failed: \(error.localizedDescription)"
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
        if let emulatorID = fresh.emulatorUUID {
            var emuDescriptor = FetchDescriptor<EmulatorProfile>(
                predicate: #Predicate { $0.id == emulatorID }
            )
            emuDescriptor.fetchLimit = 1
            guard let recovered = try? modelContext.fetch(emuDescriptor).first else {
                scanFeedback = "The emulator for this game is missing. Recreate/import the emulator, then run Scan Paths."
                return
            }
            // Force a valid relationship object before launching to avoid stale SwiftData relationship traps.
            fresh.emulator = recovered
        } else {
            fresh.emulator = nil
        }
        do {
            try GameLauncher.launch(game: fresh)
            fresh.lastPlayed = Date()
            try modelContext.save()
        } catch {
            scanFeedback = "Launch failed: \(error.localizedDescription)"
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
        let emulatorRoots = gameRoots(forEmulatorID: emulatorID)
        let snapshot = games.filter { game in
            if game.emulatorUUID == emulatorID {
                return true
            }
            return isPath(game.romPath, insideAny: emulatorRoots)
        }
        for game in snapshot {
            modelContext.delete(game)
        }
        try? modelContext.save()
    }

    private func removeAllMacGames() {
        let snapshot = games.filter { $0.emulatorUUID == nil }
        for game in snapshot {
            modelContext.delete(game)
        }
        try? modelContext.save()
    }

    private func gameRoots(forEmulatorID emulatorID: UUID) -> [String] {
        guard let emulator = emulators.first(where: { $0.id == emulatorID }) else { return [] }
        return emulator.folderPaths
            .filter { $0.resolvedPurpose == .games }
            .map { normalizedPathForComparison($0.folderPath) }
            .sorted { $0.count > $1.count }
    }

    private func isPath(_ path: String, insideAny roots: [String]) -> Bool {
        let normalizedPath = normalizedPathForComparison(path)
        for root in roots {
            if normalizedPath == root { return true }
            if normalizedPath.hasPrefix(root + "/") { return true }
        }
        return false
    }

    private func normalizedPathForComparison(_ path: String) -> String {
        var normalized = (path as NSString).standardizingPath
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }

    private func addManualMacGame() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a Mac game app or executable file."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let standardizedPath = (url.path as NSString).standardizingPath
            let normalized = normalizedPathForComparison(standardizedPath)
            DispatchQueue.main.async {
                if games.contains(where: { normalizedPathForComparison($0.romPath) == normalized }) {
                    scanFeedback = "That game is already in your library."
                    return
                }
                let baseTitle = URL(fileURLWithPath: standardizedPath).deletingPathExtension().lastPathComponent
                let title = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Mac Game" : baseTitle
                let nextSort = (games.map(\.sortOrder).max() ?? -1) + 1
                let game = LibraryGame(
                    title: title,
                    romPath: standardizedPath,
                    emulatorIDString: nil,
                    emulator: nil,
                    sortOrder: nextSort
                )
                modelContext.insert(game)
                do {
                    try modelContext.save()
                } catch {
                    scanFeedback = "Could not add game: \(error.localizedDescription)"
                }
            }
        }
    }

    @discardableResult
    private func removeOrphanedGamesFromLibrary() -> Int {
        let validIDs = activeEmulatorIDs
        var removed = 0
        for game in games {
            guard let emulatorID = game.emulatorUUID, !validIDs.contains(emulatorID) else { continue }
            modelContext.delete(game)
            removed += 1
        }
        if removed > 0 {
            try? modelContext.save()
            DebugLog.log("Cleanup: removed orphaned library games count=\(removed)")
        }
        return removed
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
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: LibraryGridMetrics.cardWidth, height: LibraryGridMetrics.titleHeight, alignment: .top)
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
                if game.emulatorUUID == nil {
                    TextField("Game path", text: pathBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Text("Edit the app/executable path for this Mac game, or choose a new target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Choose Game…", systemImage: "folder") {
                            pickGamePath()
                        }
                        Spacer()
                    }
                } else {
                    LabeledContent("File") {
                        Text(URL(fileURLWithPath: game.romPath).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
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
                            Button("Clear current cover", systemImage: "xmark.circle", role: .destructive) {
                                game.coverImageURLString = nil
                                try? modelContext.save()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !game.coverImageOptions.isEmpty {
                    Text("Detected covers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(Array(game.coverImageOptions.enumerated()), id: \.offset) { index, option in
                            HStack(spacing: 10) {
                                CoverThumbnail(urlString: option)
                                    .frame(width: 42, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(URL(string: option)?.lastPathComponent ?? option)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .textSelection(.enabled)

                                Spacer()

                                Button {
                                    setPrimaryCover(index: index)
                                } label: {
                                    Image(systemName: game.coverImageURLString == option ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.plain)
                                .help("Use as current cover")

                                Button {
                                    moveCover(from: index, direction: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                .help("Move up")

                                Button {
                                    moveCover(from: index, direction: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.plain)
                                .disabled(index >= game.coverImageOptions.count - 1)
                                .help("Move down")

                                Button(role: .destructive) {
                                    removeCover(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .help("Remove from lineup")
                            }
                            .padding(.vertical, 2)
                        }
                    }
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

    private var pathBinding: Binding<String> {
        Binding(
            get: {
                game.romPath
            },
            set: { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                game.romPath = (trimmed as NSString).standardizingPath
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
                var options = game.coverImageOptions
                let candidate = fileURL.absoluteString
                if !options.contains(candidate) {
                    options.insert(candidate, at: 0)
                }
                game.coverImageOptions = options
                game.coverImageURLString = candidate
                try? modelContext.save()
            }
        }
    }

    private func pickGamePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let path = (url.path as NSString).standardizingPath
            DispatchQueue.main.async {
                game.romPath = path
                try? modelContext.save()
            }
        }
    }

    private func setPrimaryCover(index: Int) {
        let options = game.coverImageOptions
        guard options.indices.contains(index) else { return }
        game.coverImageURLString = options[index]
        try? modelContext.save()
    }

    private func removeCover(at index: Int) {
        var options = game.coverImageOptions
        guard options.indices.contains(index) else { return }
        let removed = options.remove(at: index)
        game.coverImageOptions = options
        if game.coverImageURLString == removed {
            game.coverImageURLString = options.first
        }
        try? modelContext.save()
    }

    private func moveCover(from index: Int, direction: Int) {
        var options = game.coverImageOptions
        guard options.indices.contains(index) else { return }
        let target = index + direction
        guard options.indices.contains(target) else { return }
        let item = options.remove(at: index)
        options.insert(item, at: target)
        game.coverImageOptions = options
        try? modelContext.save()
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

private struct ScreenScraperLibrarySettingsView: View {
    let isConfigured: Bool
    let onOpenCredentials: () -> Void
    let onScrapeNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screen Scrapper")
                .font(.title3.weight(.semibold))
            Text("Manage ScreenScraper login credentials and run a full metadata scrape for your library.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Login / Credentials", systemImage: "person.badge.key") {
                    onOpenCredentials()
                }
                Button("Scrape Library Now", systemImage: "sparkle.magnifyingglass") {
                    onScrapeNow()
                }
                .disabled(!isConfigured)
            }

            if isConfigured {
                Text("Credentials saved. Scrape will append ScreenScraper art to each game’s cover list and apply emulator cover-priority preference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Set ScreenScraper credentials first, then run scrape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
