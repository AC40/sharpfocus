import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlays = OverlayController()
    private let tracker = FocusTracker()
    private let capture = CaptureEngine()

    private let alwaysAppsMenu = NSMenu()
    private var enableItem: NSMenuItem!
    private var focusedWindowItem: NSMenuItem!
    private var frontAppItem: NSMenuItem!
    private var pinItem: NSMenuItem!
    private var clearPinsItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var engineItems: [FilterEngine: NSMenuItem] = [:]
    private var engineStatusItemMenu: NSMenuItem!
    private var missionControlItem: NSMenuItem!
    private var grayscaleSlider: SliderMenuItem!
    private var dimmingSlider: SliderMenuItem!
    private var blurSlider: SliderMenuItem!

    /// The engine currently driving the overlay (resolved, not just selected).
    private var activeEngine: FilterEngine?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpHotKeys()

        tracker.onUpdate = { [weak self] holes in
            self?.overlays.setHoles(holes)
        }

        // The system occasionally kills capture streams (e.g. TCC re-checks,
        // display sleep). Restart with a debounce so a frozen frame never sticks.
        capture.onStreamStopped = { [weak self] in
            self?.scheduleCaptureRestart()
        }

        // Mission Control & friends animate every window; hiding the overlay
        // for the duration removes our compositing cost from that animation.
        tracker.onMissionControlChange = { [weak self] active in
            guard let self, Settings.shared.enabled, Settings.shared.pauseInMissionControl
            else { return }
            NSLog("SharpFocus: Mission Control \(active ? "entered — overlay paused" : "left — overlay resumed")")
            if active {
                self.overlays.hide()
                self.capture.setPaused(true)
            } else {
                self.overlays.show()
                self.capture.setPaused(false)
            }
        }

        setUpCommandChannel()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .sharpFocusSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if !CaptureEngine.hasScreenRecordingPermission {
            // Triggers the system prompt on first launch; until granted,
            // the overlay falls back to dim-only.
            CGRequestScreenCaptureAccess()
        }

        if Settings.shared.enabled {
            activateOverlay()
        }
        refreshMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Streams are torn down by the OS with the process; nothing to wait for.
    }

    private var restartScheduled = false

    private func scheduleCaptureRestart() {
        guard Settings.shared.enabled, activeEngine == .capture, !restartScheduled else { return }
        restartScheduled = true
        NSLog("SharpFocus: scheduling capture restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.restartScheduled = false
            guard Settings.shared.enabled, self.activeEngine == .capture else { return }
            self.startCapture()
        }
    }

    // MARK: - Command channel (sfctl)

    /// Lets the `sfctl` CLI drive settings in the running app, e.g.
    /// `sfctl engine backdrop`, `sfctl blur 15`, `sfctl grayscale 0.8`.
    private func setUpCommandChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("de.beyond925.SharpFocus.command"),
            object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String else { return }
            let parts = command.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                NSLog("SharpFocus: ignoring malformed command '\(command)'")
                return
            }
            let settings = Settings.shared
            switch (parts[0], parts[1]) {
            case ("engine", let value):
                if let engine = FilterEngine(rawValue: value) { settings.engine = engine }
            case ("mode", let value):
                if let mode = FollowMode(rawValue: value) { settings.followMode = mode }
            case ("grayscale", let value):
                if let number = Double(value) { settings.grayscale = number }
            case ("blur", let value):
                if let number = Double(value) { settings.blurRadius = number }
            case ("dim", let value):
                if let number = Double(value) { settings.dimming = number }
            case ("enabled", let value):
                settings.enabled = value == "1" || value == "true"
            case ("mc-pause", let value):
                settings.pauseInMissionControl = value == "1" || value == "true"
            default:
                NSLog("SharpFocus: unknown command '\(command)'")
                return
            }
            NSLog("SharpFocus: applied command '\(command)'")
        }
    }

    // MARK: - Overlay activation

    private func activateOverlay() {
        let engine = FilterEngine.resolve(Settings.shared.engine)
        activeEngine = engine
        NSLog("SharpFocus: engine \(Settings.shared.engine.rawValue) resolved to \(engine.rawValue)")

        overlays.rebuild(engine: engine)
        overlays.show()
        tracker.start()

        if engine == .capture {
            startCapture()
        }
    }

    private func deactivateOverlay() {
        tracker.stop()
        overlays.tearDown()
        activeEngine = nil
        Task { [capture] in await capture.stop() }
    }

    private func startCapture() {
        let windowNumbers = overlays.windows.map(\.windowNumber)
        let layers = overlays.captureLayersByDisplay
        Task { [capture] in
            await capture.start(excludedWindowNumbers: windowNumbers, layersByDisplay: layers)
        }
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

        permissionItem = menu.addItem(
            withTitle: "Grant Screen Recording for grayscale…",
            action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        permissionItem.target = self

        menu.addItem(.separator())

        let followHeader = menu.addItem(withTitle: "Keep in Color", action: nil, keyEquivalent: "")
        followHeader.isEnabled = false

        focusedWindowItem = menu.addItem(
            withTitle: "Focused Window Only", action: #selector(selectFocusedWindowMode),
            keyEquivalent: "")
        focusedWindowItem.target = self
        focusedWindowItem.indentationLevel = 1

        frontAppItem = menu.addItem(
            withTitle: "All Windows of Active App", action: #selector(selectFrontAppMode),
            keyEquivalent: "")
        frontAppItem.target = self
        frontAppItem.indentationLevel = 1

        let alwaysItem = menu.addItem(withTitle: "Always in Focus", action: nil, keyEquivalent: "")
        alwaysItem.submenu = alwaysAppsMenu
        alwaysAppsMenu.delegate = self

        pinItem = menu.addItem(
            withTitle: "Pin Focused Window", action: #selector(pinFocusedWindow), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .option, .control]
        pinItem.target = self

        clearPinsItem = menu.addItem(
            withTitle: "Clear Pinned Windows", action: #selector(clearPinnedWindows),
            keyEquivalent: "")
        clearPinsItem.target = self

        menu.addItem(.separator())

        let engineMenu = NSMenu()
        let engineHeader = menu.addItem(withTitle: "Engine", action: nil, keyEquivalent: "")
        engineHeader.submenu = engineMenu
        for engine in FilterEngine.allCases {
            let item = NSMenuItem(
                title: engine.displayName, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            engineMenu.addItem(item)
            engineItems[engine] = item
        }
        engineMenu.addItem(.separator())
        engineStatusItemMenu = engineMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        engineStatusItemMenu.isEnabled = false

        grayscaleSlider = SliderMenuItem(
            title: "Grayscale", value: Settings.shared.grayscale, range: 0...1
        ) { Settings.shared.grayscale = $0 }
        menu.addItem(grayscaleSlider)

        blurSlider = SliderMenuItem(
            title: "Blur", value: Settings.shared.blurRadius, range: 0...40,
            format: { String(format: "%.0f px", $0) }
        ) { Settings.shared.blurRadius = $0 }
        menu.addItem(blurSlider)

        dimmingSlider = SliderMenuItem(
            title: "Dimming", value: Settings.shared.dimming, range: 0...0.9
        ) { Settings.shared.dimming = $0 }
        menu.addItem(dimmingSlider)

        menu.addItem(.separator())

        missionControlItem = menu.addItem(
            withTitle: "Pause in Mission Control", action: #selector(toggleMissionControlPause),
            keyEquivalent: "")
        missionControlItem.target = self

        menu.addItem(.separator())
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
        focusedWindowItem.state = settings.followMode == .focusedWindow ? .on : .off
        frontAppItem.state = settings.followMode == .frontApp ? .on : .off
        permissionItem.isHidden =
            CaptureEngine.hasScreenRecordingPermission || settings.engine != .capture

        let availability = FilterEngine.availability
        for (engine, item) in engineItems {
            item.state = settings.engine == engine ? .on : .off
            let available = availability[engine] ?? false
            item.title = available ? engine.displayName : engine.displayName + " — unavailable"
        }
        let resolved = activeEngine ?? FilterEngine.resolve(settings.engine)
        engineStatusItemMenu.title = resolved == settings.engine
            ? "Active: \(resolved.rawValue)"
            : "Active: \(resolved.rawValue) (fallback from \(settings.engine.rawValue))"

        missionControlItem.state = settings.pauseInMissionControl ? .on : .off
        grayscaleSlider.update(value: settings.grayscale)
        blurSlider.update(value: settings.blurRadius)
        dimmingSlider.update(value: settings.dimming)

        let pinCount = tracker.pinnedWindowIDs.count
        clearPinsItem.isHidden = pinCount == 0
        clearPinsItem.title = "Clear Pinned Windows (\(pinCount))"

        statusItem.button?.appearsDisabled = !settings.enabled
    }

    // MARK: - Menu delegate (dynamic "Always in Focus" app list)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === alwaysAppsMenu {
            rebuildAlwaysAppsMenu()
        } else {
            refreshMenuState()
        }
    }

    private func rebuildAlwaysAppsMenu() {
        alwaysAppsMenu.removeAllItems()
        let selected = Settings.shared.alwaysApps

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        // Keep selected-but-not-running apps visible so they can be unchecked.
        let runningIDs = Set(apps.compactMap(\.bundleIdentifier))
        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let item = NSMenuItem(
                title: app.localizedName ?? bundleID,
                action: #selector(toggleAlwaysApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = selected.contains(bundleID) ? .on : .off
            if let icon = app.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            alwaysAppsMenu.addItem(item)
        }
        for bundleID in selected.subtracting(runningIDs).sorted() {
            let item = NSMenuItem(
                title: bundleID, action: #selector(toggleAlwaysApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = .on
            alwaysAppsMenu.addItem(item)
        }
        if alwaysAppsMenu.items.isEmpty {
            let empty = alwaysAppsMenu.addItem(
                withTitle: "No running apps", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
    }

    @objc private func selectFocusedWindowMode() { Settings.shared.followMode = .focusedWindow }
    @objc private func selectFrontAppMode() { Settings.shared.followMode = .frontApp }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = FilterEngine(rawValue: raw) else { return }
        Settings.shared.engine = engine
    }

    @objc private func toggleMissionControlPause() {
        Settings.shared.pauseInMissionControl.toggle()
    }

    @objc private func toggleAlwaysApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Settings.shared.toggleAlwaysApp(bundleID)
    }

    @objc private func pinFocusedWindow() {
        tracker.togglePinFocusedWindow()
        refreshMenuState()
    }

    @objc private func clearPinnedWindows() {
        tracker.clearPinnedWindows()
        refreshMenuState()
    }

    @objc private func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Change handling

    @objc private func settingsChanged() {
        let settings = Settings.shared
        if settings.enabled, overlays.windows.isEmpty {
            activateOverlay()
        } else if !settings.enabled, !overlays.windows.isEmpty {
            deactivateOverlay()
        } else if settings.enabled {
            let engine = FilterEngine.resolve(settings.engine)
            if engine != activeEngine {
                NSLog("SharpFocus: switching engine \(activeEngine?.rawValue ?? "-") -> \(engine.rawValue)")
                let previous = activeEngine
                activeEngine = engine
                if previous == .capture {
                    Task { [capture] in await capture.stop() }
                }
                if engine == .capture {
                    startCapture()
                }
            }
            overlays.applyAppearance(engine: engine)
            tracker.poll(force: true)
        }
        refreshMenuState()
    }

    @objc private func screensChanged() {
        guard Settings.shared.enabled else { return }
        deactivateOverlay()
        activateOverlay()
    }
}
