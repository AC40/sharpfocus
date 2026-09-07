import AppKit

extension AppDelegate {

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.lefthalf.filled",
            accessibilityDescription: "Sharp Focus")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        enableItem = menu.addItem(
            withTitle: "Enable Sharp Focus", action: #selector(toggleEnabled), keyEquivalent: "f")
        enableItem.keyEquivalentModifierMask = [.command, .option, .control]
        enableItem.target = self

        snoozeItem = menu.addItem(withTitle: "Snooze", action: nil, keyEquivalent: "")
        snoozeItem.submenu = snoozeMenu
        snoozeMenu.delegate = self

        menu.addItem(.separator())

        let presetsItem = menu.addItem(withTitle: "Presets", action: nil, keyEquivalent: "")
        presetsItem.submenu = presetsMenu
        presetsMenu.delegate = self

        pinItem = menu.addItem(
            withTitle: "Pin Focused Window", action: #selector(pinFocusedWindow), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .option, .control]
        pinItem.target = self

        clearPinsItem = menu.addItem(
            withTitle: "Clear Pinned Windows", action: #selector(clearPinnedWindows), keyEquivalent: "")
        clearPinsItem.target = self

        menu.addItem(.separator())

        if !Backdrop.isAvailable {
            let warning = menu.addItem(
                withTitle: "Grayscale and blur not available. Dimming only.",
                action: nil, keyEquivalent: "")
            warning.isEnabled = false
        }

        let settingsItem = menu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self

        let quit = menu.addItem(
            withTitle: "Quit Sharp Focus", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]

        statusItem.menu = menu
    }

    func syncHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        if let toggle = Settings.shared.toggleShortcut {
            HotKeyCenter.shared.register(toggle) { [weak self] in self?.toggleEnabled() }
        }
        if let pin = Settings.shared.pinShortcut {
            HotKeyCenter.shared.register(pin) { [weak self] in self?.pinFocusedWindow() }
        }
        applyShortcutsToMenu()
    }

    func applyShortcutsToMenu() {
        applyShortcut(Settings.shared.toggleShortcut, to: enableItem)
        if pinItem != nil { applyShortcut(Settings.shared.pinShortcut, to: pinItem) }
    }

    func applyShortcut(_ shortcut: KeyShortcut?, to item: NSMenuItem) {
        guard let shortcut, !shortcut.menuKeyEquivalent.isEmpty else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.cocoaModifiers
    }

    func refreshMenuState() {
        let settings = Settings.shared
        enableItem.state = settings.isEffectivelyEnabled ? .on : .off

        if let until = settings.snoozedUntil, settings.isSnoozed {
            snoozeItem.title = "Snoozed until \(Self.timeFormatter.string(from: until))"
            snoozeItem.isEnabled = true
        } else {
            snoozeItem.title = "Snooze"
            snoozeItem.isEnabled = settings.enabled
        }

        let pinCount = tracker.pinnedWindowIDs.count
        clearPinsItem.isHidden = pinCount == 0
        clearPinsItem.title = "Clear Pinned Windows (\(pinCount))"

        statusItem.button?.appearsDisabled = !settings.isEffectivelyEnabled
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === presetsMenu {
            rebuildPresetsMenu()
        } else if menu === snoozeMenu {
            rebuildSnoozeMenu()
        } else {
            refreshMenuState()
        }
    }

    func rebuildPresetsMenu() {
        presetsMenu.removeAllItems()
        let settings = Settings.shared
        let active = settings.activePresetID
        for preset in settings.presets {
            let item = NSMenuItem(
                title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id.uuidString
            item.state = preset.id == active ? .on : .off
            presetsMenu.addItem(item)
        }
        if settings.presets.isEmpty {
            let empty = presetsMenu.addItem(withTitle: "No presets", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        presetsMenu.addItem(.separator())
        let save = presetsMenu.addItem(
            withTitle: "Save Current as Preset…", action: #selector(saveCurrentAsPreset),
            keyEquivalent: "")
        save.target = self
        let edit = presetsMenu.addItem(
            withTitle: "Edit Presets…", action: #selector(openPresetSettings), keyEquivalent: "")
        edit.target = self
    }

    func rebuildSnoozeMenu() {
        snoozeMenu.removeAllItems()
        if Settings.shared.isSnoozed {
            let resume = snoozeMenu.addItem(
                withTitle: "Resume Now", action: #selector(resumeFromSnooze), keyEquivalent: "")
            resume.target = self
            snoozeMenu.addItem(.separator())
        }
        for (title, minutes) in [("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120)] {
            let item = snoozeMenu.addItem(
                withTitle: title, action: #selector(snoozeSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
        }
    }
}
