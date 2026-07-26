import Foundation

/// Persists user-edited launch argument templates for built-in catalog profiles (bundle JSON is read-only).
public enum CatalogLaunchArgumentOverrides {
    private static let userDefaultsKey = "GBear.CatalogLaunchArgumentOverrides.v1"
    private static let legacyUserDefaultsKey = "MacGameLibrary.CatalogLaunchArgumentOverrides.v1"

    private static func loadMap() -> [Int: String] {
        migrateLegacyUserDefaultsIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
    }

    private static func saveMap(_ map: [Int: String]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private static func migrateLegacyUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: userDefaultsKey) == nil,
              let legacy = defaults.data(forKey: legacyUserDefaultsKey) else { return }
        defaults.set(legacy, forKey: userDefaultsKey)
        defaults.removeObject(forKey: legacyUserDefaultsKey)
    }

    /// Effective template: user override when present, otherwise the catalog default.
    public static func effectiveStartupArguments(for record: BuiltinEmulatorProfileRecord) -> String {
        loadMap()[record.catalogId] ?? record.startupArguments
    }

    public static func setEffectiveStartupArguments(_ value: String, catalogId: Int) {
        var map = loadMap()
        map[catalogId] = LaunchArgumentTemplate.normalizePCSX2StyleBootSeparator(
            LaunchArgumentTemplate.normalizeHomePaths(value)
        )
        saveMap(map)
    }

    /// Rewrites absolute home paths in catalog overrides to `/Users/{user_name}/...`.
    public static func normalizeHomePathsInOverrides() {
        let map = loadMap()
        guard !map.isEmpty else { return }
        var updated: [Int: String] = [:]
        var changed = false
        for (id, value) in map {
            let normalized = LaunchArgumentTemplate.normalizeHomePaths(value)
            updated[id] = normalized
            if normalized != value { changed = true }
        }
        if changed {
            saveMap(updated)
        }
    }

    /// Upgrades PCSX2/ARMSX2-style overrides that are missing the `--` boot separator.
    public static func normalizePCSX2StyleBootSeparatorsInOverrides() {
        let map = loadMap()
        guard !map.isEmpty else { return }
        var updated: [Int: String] = [:]
        var changed = false
        for (id, value) in map {
            let normalized = LaunchArgumentTemplate.normalizePCSX2StyleBootSeparator(value)
            updated[id] = normalized
            if normalized != value { changed = true }
        }
        if changed {
            saveMap(updated)
        }
    }
}
