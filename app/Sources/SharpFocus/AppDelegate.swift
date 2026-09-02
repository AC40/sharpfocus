import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlays = OverlayController()
    private let tracker = FocusTracker()
    private lazy var automation = AutomationEngine(focusProvider: FocusModeMonitor.shared)

    private var enableItem: NSMenuItem!
    private var snoozeItem: NSMenuItem!
    private let snoozeMenu = NSMenu()
    private let presetsMenu = NSMenu()
    private var pinItem: NSMenuItem!
    private var clearPinsItem: NSMenuItem!
    private var unavailableItem: NSMenuItem!

    private var snoozeUntil: Date?
    private var snoozeTimer: Timer?

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpHotKeys()
        setUpCommandChannel()

        tracker.onUpdate = { [weak self] holes in
            self?.overlays.setHoles(holes)
        }

        // Mission Control & friends animate every window; hiding the overlay
        // for the duration removes our compositing cost from that animation.
        tracker.onMissionControlChange = { [weak self] active in
            guard let self, Settings.shared.enabled, Settings.shared.pauseInMissionControl
            else { return }
            NSLog("SharpFocus: Mission Control \(active ? "entered — overlay paused" : "left — overlay resumed")")
            active ? self.overlays.hide() : self.overlays.show()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .sharpFocusSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if !Backdrop.isAvailable {
            NSLog("SharpFocus: CABackdropLayer unavailable — dimming only")
        }
        if Settings.shared.enabled {
            activateOverlay()
        }
        automation.start()
        refreshMenuState()
    }

    // MARK: - Overlay activation

    private func activateOverlay() {
        overlays.rebuild()
        overlays.show()
        tracker.start()
    }

    private func deactivateOverlay() {
        tracker.stop()
        overlays.tearDown()
    }

    // MARK: - Status item & menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.lefthalf.filled",
            accessibilityDescription: "Sharp Focus")

        let menu = NSMenu()
        menu.delegate = self

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

        unavailableItem = menu.addItem(
            withTitle: "Grayscale & blur unavailable on this macOS — dimming only",
            action: nil, keyEquivalent: "")
        unavailableItem.isEnabled = false
        unavailableItem.isHidden = Backdrop.isAvailable

        let settingsItem = menu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let quit = menu.addItem(
            withTitle: "Quit Sharp Focus", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]

        statusItem.menu = menu
    }

    private func setUpHotKeys() {
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        HotKeyCenter.shared.register(keyCode: UInt32(kVK_ANSI_F), modifiers: modifiers) { [weak self] in
            self?.toggleEnabled()
        }
        HotKeyCenter.shared.register(keyCode: UInt32(kVK_ANSI_P), modifiers: modifiers) { [weak self] in
            self?.pinFocusedWindow()
        }
    }

    private func refreshMenuState() {
        let settings = Settings.shared
        enableItem.state = settings.enabled ? .on : .off
        if let until = snoozeUntil {
            snoozeItem.title = "Snoozed until \(Self.timeFormatter.string(from: until))"
        } else {
            snoozeItem.title = "Snooze"
        }
        snoozeItem.isEnabled = settings.enabled || snoozeUntil != nil

        let pinCount = tracker.pinnedWindowIDs.count
        clearPinsItem.isHidden = pinCount == 0
        clearPinsItem.title = "Clear Pinned Windows (\(pinCount))"

        statusItem.button?.appearsDisabled = !settings.enabled
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Menu delegate (dynamic submenus)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === presetsMenu {
            rebuildPresetsMenu()
        } else if menu === snoozeMenu {
            rebuildSnoozeMenu()
        } else {
            refreshMenuState()
        }
    }

    private func rebuildPresetsMenu() {
        presetsMenu.removeAllItems()
        let settings = Settings.shared
        let active = settings.activePreset?.id
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

    private func rebuildSnoozeMenu() {
        snoozeMenu.removeAllItems()
        if snoozeUntil != nil {
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

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let preset = Settings.shared.presets.first(where: { $0.id == id })
        else { return }
        Settings.shared.apply(preset)
    }

    @objc private func saveCurrentAsPreset() {
        let settings = Settings.shared
        _ = settings.captureCurrentAsPreset(named: "Preset \(settings.presets.count + 1)")
        SettingsWindowController.shared.show(tab: .presets)
    }

    @objc private func openPresetSettings() {
        SettingsWindowController.shared.show(tab: .presets)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func snoozeSelected(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        snooze(minutes: minutes)
    }

    @objc private func resumeFromSnooze() {
        cancelSnooze()
        Settings.shared.enabled = true
    }

    @objc private func pinFocusedWindow() {
        tracker.togglePinFocusedWindow()
        refreshMenuState()
    }

    @objc private func clearPinnedWindows() {
        tracker.clearPinnedWindows()
        refreshMenuState()
    }

    // MARK: - Snooze

    private func snooze(minutes: Int) {
        cancelSnooze()
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        snoozeUntil = until
        Settings.shared.enabled = false
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            self?.snoozeUntil = nil
            self?.snoozeTimer = nil
            Settings.shared.enabled = true
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
        NSLog("SharpFocus: snoozed for \(minutes) min")
        refreshMenuState()
    }

    private func cancelSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeUntil = nil
    }

    // MARK: - Remote control (sfctl + sharpfocus:// URLs)

    private func setUpCommandChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("de.beyond925.SharpFocus.command"),
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let line = note.object as? String else { return }
            guard let command = Command.parse(line: line) else {
                NSLog("SharpFocus: unknown command '\(line)'")
                return
            }
            NSLog("SharpFocus: sfctl -> \(self.perform(command))")
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string)
        else { return }
        let commands = Command.parse(url: url)
        if commands.isEmpty {
            NSLog("SharpFocus: unrecognized URL \(string)")
        }
        for command in commands {
            NSLog("SharpFocus: url -> \(perform(command))")
        }
    }

    @discardableResult
    private func perform(_ command: Command) -> String {
        let settings = Settings.shared
        switch command {
        case .setEnabled(let on):
            if on { cancelSnooze() }
            settings.enabled = on
            return "enabled=\(on)"
        case .toggle:
            if !settings.enabled { cancelSnooze() }
            settings.enabled.toggle()
            return "enabled=\(settings.enabled)"
        case .grayscale(let value):
            settings.grayscale = value
            return "grayscale=\(settings.grayscale)"
        case .blur(let value):
            settings.blurRadius = value
            return "blur=\(settings.blurRadius)"
        case .dim(let value):
            settings.dimming = value
            return "dim=\(settings.dimming)"
        case .mode(let mode):
            settings.followMode = mode
            return "mode=\(mode.rawValue)"
        case .preset(let name):
            guard let preset = settings.presets.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else { return "no preset named '\(name)'" }
            settings.apply(preset)
            if !settings.enabled { cancelSnooze(); settings.enabled = true }
            return "preset=\(preset.name)"
        case .snooze(let minutes):
            snooze(minutes: max(1, minutes))
            return "snoozed \(minutes) min"
        case .pauseInMissionControl(let on):
            settings.pauseInMissionControl = on
            return "mc-pause=\(on)"
        case .openSettings:
            SettingsWindowController.shared.show()
            return "settings opened"
        }
    }

    // MARK: - Change handling

    @objc private func settingsChanged() {
        let settings = Settings.shared
        if settings.enabled, overlays.windows.isEmpty {
            activateOverlay()
        } else if !settings.enabled, !overlays.windows.isEmpty {
            deactivateOverlay()
        } else if settings.enabled {
            overlays.applyAppearance()
            tracker.poll(force: true)
        }
        // Re-enabling by hand ends any running snooze.
        if settings.enabled, snoozeUntil != nil {
            cancelSnooze()
        }
        refreshMenuState()
    }

    @objc private func screensChanged() {
        guard Settings.shared.enabled else { return }
        deactivateOverlay()
        activateOverlay()
    }
}
