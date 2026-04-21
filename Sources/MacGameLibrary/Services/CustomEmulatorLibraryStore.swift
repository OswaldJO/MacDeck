import Foundation

/// User-added presets (name + default launch arguments) that appear alongside the bundled catalog.
public struct CustomEmulatorLibraryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayTitle: String
    public var startupArguments: String

    public init(id: UUID = UUID(), displayTitle: String, startupArguments: String) {
        self.id = id
        self.displayTitle = displayTitle
        self.startupArguments = startupArguments
    }
}

public enum CustomEmulatorLibraryStore {
    private static let udKey = "MacGameLibrary.CustomEmulatorLibraryEntries.v1"

    public static func allEntries() -> [CustomEmulatorLibraryEntry] {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([CustomEmulatorLibraryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func save(_ entries: [CustomEmulatorLibraryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    @discardableResult
    public static func add(displayTitle: String, startupArguments: String) -> CustomEmulatorLibraryEntry {
        var list = allEntries()
        let entry = CustomEmulatorLibraryEntry(
            displayTitle: displayTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            startupArguments: startupArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        list.append(entry)
        save(list)
        return entry
    }

    public static func update(id: UUID, displayTitle: String, startupArguments: String) {
        var list = allEntries()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].displayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        list[i].startupArguments = startupArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        save(list)
    }

    public static func remove(id: UUID) {
        save(allEntries().filter { $0.id != id })
    }
}
