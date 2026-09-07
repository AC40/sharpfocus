import Foundation

extension Settings {

    var toggleShortcut: KeyShortcut? {
        get { loadShortcut(forKey: Key.toggleShortcut, default: .defaultToggle) }
        set { storeShortcut(newValue, forKey: Key.toggleShortcut) }
    }

    var pinShortcut: KeyShortcut? {
        get { loadShortcut(forKey: Key.pinShortcut, default: .defaultPin) }
        set { storeShortcut(newValue, forKey: Key.pinShortcut) }
    }

    var shortcutsConflict: Bool {
        guard let toggle = toggleShortcut, let pin = pinShortcut else { return false }
        return toggle == pin
    }

    func resetShortcutsToDefaults() {
        batch {
            toggleShortcut = .defaultToggle
            pinShortcut = .defaultPin
        }
    }

    func loadShortcut(forKey key: String, default defaultValue: KeyShortcut) -> KeyShortcut? {
        guard let data = defaults.data(forKey: key) else { return defaultValue }
        if let decoded = try? JSONDecoder().decode(KeyShortcut?.self, from: data) {
            return decoded
        }
        return defaultValue
    }

    func storeShortcut(_ shortcut: KeyShortcut?, forKey key: String) {
        if let shortcut {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(Optional<KeyShortcut>.none), forKey: key)
        }
        changed()
    }
}
