import Foundation

extension Notification.Name {
    static let profilesChanged = Notification.Name("incy.profilesChanged")
    static let vpnChanged = Notification.Name("incy.vpnChanged")
    static let vpnError = Notification.Name("incy.vpnError")
}

final class ProfileStore {
    static let shared = ProfileStore()
    private let defaults = UserDefaults.standard
    private(set) var profiles = [Profile]()
    private(set) var loadError: String?
    var selected: Profile? { profiles.first { $0.id == defaults.string(forKey: "selectedID") } ?? profiles.first }
    var dns: String {
        get { defaults.string(forKey: "dns") ?? "1.1.1.1" }
        set { defaults.set(newValue, forKey: "dns"); changed() }
    }
    private init() {
        for id in defaults.stringArray(forKey: "profileIDs") ?? [] {
            do { profiles.append(try ProfileVault.load(id)) }
            catch { loadError = "Не удалось прочитать часть профилей из Keychain. Проверьте подпись приложения." }
        }
    }
    private func equivalent(_ a: Profile, _ b: Profile) -> Bool {
        var left = a; var right = b
        left.id = ""; right.id = ""; left.name = ""; right.name = ""
        return left == right
    }
    func add(_ incoming: [Profile]) throws {
        guard loadError == nil else { throw ProfileError.invalid(loadError!) }
        var inserted = [Profile]()
        do {
            for p in incoming {
                try p.validate()
                if (profiles + inserted).contains(where: { equivalent($0, p) }) { continue }
                guard profiles.count + inserted.count < 256 else { throw ProfileError.invalid("Максимум 256 профилей.") }
                try ProfileVault.save(p); inserted.append(p)
            }
        } catch { for p in inserted { try? ProfileVault.delete(p.id) }; throw error }
        profiles += inserted
        if defaults.string(forKey: "selectedID") == nil { defaults.set(profiles.first?.id, forKey: "selectedID") }
        persist()
    }
    func select(_ p: Profile) { defaults.set(p.id, forKey: "selectedID"); changed() }
    func rename(_ p: Profile, to name: String) throws {
        var updated = p; updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { throw ProfileError.invalid("Введите имя профиля.") }
        try updated.validate(); try ProfileVault.save(updated)
        if let index = profiles.firstIndex(where: { $0.id == p.id }) { profiles[index] = updated }
        persist()
    }
    func delete(_ p: Profile) throws {
        guard loadError == nil else { throw ProfileError.invalid(loadError!) }
        try ProfileVault.delete(p.id); profiles.removeAll { $0.id == p.id }
        if defaults.string(forKey: "selectedID") == p.id { defaults.set(profiles.first?.id, forKey: "selectedID") }
        persist()
    }
    private func persist() { defaults.set(profiles.map { $0.id }, forKey: "profileIDs"); changed() }
    private func changed() { NotificationCenter.default.post(name: .profilesChanged, object: nil) }
}

