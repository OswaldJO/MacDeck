import Foundation

@Observable
final class ControllerMappingStore {
    private(set) var profiles: [ControllerMappingProfile] = []

    var selectedProfileID: UUID?

    private let fileURL = PersistenceStoreLocation.directoryURL.appending(path: "controller_mappings.json")
    private var suppressSave = false

    init() {
        suppressSave = true
        load()
        if profiles.isEmpty {
            let p = ControllerMappingProfile(name: "Default")
            profiles = [p]
            selectedProfileID = p.id
        } else if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
        suppressSave = false
        save()
    }

    func selectProfile(id: UUID?) {
        selectedProfileID = id
        save()
    }

    var selectedProfile: ControllerMappingProfile? {
        guard let id = selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == id }
    }

    func addProfile(named name: String) {
        let p = ControllerMappingProfile(name: name)
        profiles.append(p)
        selectedProfileID = p.id
        save()
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if profiles.isEmpty {
            let p = ControllerMappingProfile(name: "Default")
            profiles = [p]
            selectedProfileID = p.id
        } else if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
        save()
    }

    func renameProfile(id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        save()
    }

    func addBinding(_ binding: ControllerBinding) {
        guard var p = selectedProfile else { return }
        p.bindings.removeAll { $0.sourceElementID == binding.sourceElementID }
        p.bindings.append(binding)
        replaceProfile(p)
    }

    func removeBinding(id: UUID) {
        guard var p = selectedProfile else { return }
        p.bindings.removeAll { $0.id == id }
        replaceProfile(p)
    }

    private func replaceProfile(_ p: ControllerMappingProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == p.id }) else { return }
        profiles[idx] = p
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            return
        }
        profiles = decoded.profiles
        selectedProfileID = decoded.selectedProfileID
    }

    private func save() {
        let payload = Payload(profiles: profiles, selectedProfileID: selectedProfileID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct Payload: Codable {
        var profiles: [ControllerMappingProfile]
        var selectedProfileID: UUID?
    }
}
