import Foundation

/// User-added presets (name + default launch arguments) that appear alongside the bundled catalog.
public struct CustomEmulatorLibraryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayTitle: String
    public var startupArguments: String
    public var supportedFileTypesCSV: String

    public init(id: UUID = UUID(), displayTitle: String, startupArguments: String, supportedFileTypesCSV: String = "") {
        self.id = id
        self.displayTitle = displayTitle
        self.startupArguments = startupArguments
        self.supportedFileTypesCSV = supportedFileTypesCSV
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayTitle
        case startupArguments
        case supportedFileTypesCSV
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayTitle = try container.decode(String.self, forKey: .displayTitle)
        startupArguments = try container.decode(String.self, forKey: .startupArguments)
        supportedFileTypesCSV = try container.decodeIfPresent(String.self, forKey: .supportedFileTypesCSV) ?? ""
    }
}

public enum CustomEmulatorLibraryStore {
    private static let udKey = "GBear.CustomEmulatorLibraryEntries.v1"
    private static let legacyUdKey = "MacGameLibrary.CustomEmulatorLibraryEntries.v1"

    public static func allEntries() -> [CustomEmulatorLibraryEntry] {
        migrateLegacyUserDefaultsIfNeeded()
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
    public static func add(displayTitle: String, startupArguments: String, supportedFileTypesCSV: String = "") -> CustomEmulatorLibraryEntry {
        var list = allEntries()
        let entry = CustomEmulatorLibraryEntry(
            displayTitle: displayTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            startupArguments: startupArguments.trimmingCharacters(in: .whitespacesAndNewlines),
            supportedFileTypesCSV: supportedFileTypesCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        list.append(entry)
        save(list)
        return entry
    }

    public static func update(id: UUID, displayTitle: String, startupArguments: String, supportedFileTypesCSV: String = "") {
        var list = allEntries()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].displayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        list[i].startupArguments = startupArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        list[i].supportedFileTypesCSV = supportedFileTypesCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        save(list)
    }

    public static func remove(id: UUID) {
        save(allEntries().filter { $0.id != id })
    }

    private static func migrateLegacyUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: udKey) == nil,
              let legacy = defaults.data(forKey: legacyUdKey) else { return }
        defaults.set(legacy, forKey: udKey)
        defaults.removeObject(forKey: legacyUdKey)
    }
}
