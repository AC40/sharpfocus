import AppKit

extension AppDelegate {

    @objc func toggleEnabled() {
        let settings = Settings.shared
        if settings.isSnoozed {
            settings.snoozedUntil = nil
        } else {
            settings.enabled.toggle()
        }
    }

    @objc func selectPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let preset = Settings.shared.presets.first(where: { $0.id == id })
        else { return }
        Settings.shared.apply(preset)
        Settings.shared.enabled = true
    }

    @objc func saveCurrentAsPreset() {
        Settings.shared.captureCurrentAsPreset()
        SettingsWindowController.shared.show(tab: .presets)
    }

    @objc func openPresetSettings() {
        SettingsWindowController.shared.show(tab: .presets)
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc func openSettingsFromMenu(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func openOnboarding() {
        OnboardingWindowController.shared.show()
    }

    @objc func pinFocusedWindow() {
        tracker.togglePinFocusedWindow()
        refreshMenuState()
    }

    @objc func clearPinnedWindows() {
        tracker.clearPinnedWindows()
        refreshMenuState()
    }

    func setUpCommandChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.acrichter.SharpFocus.command"),
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

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
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
    func perform(_ command: Command) -> String {
        let settings = Settings.shared
        switch command {
        case .setEnabled(let on):
            settings.batch {
                settings.snoozedUntil = nil
                settings.enabled = on
            }
            return "enabled=\(on)"
        case .toggle:
            toggleEnabled()
            return "enabled=\(settings.isEffectivelyEnabled)"
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
        case .focusedStaysGrayscale(let on):
            settings.focusedStaysGrayscale = on
            return "focusedGray=\(on)"
        case .preset(let name):
            let key = name.presetLookupKey
            guard let preset = settings.presets.first(where: { $0.name.presetLookupKey == key })
            else { return "no preset named '\(name)'" }
            settings.batch {
                settings.apply(preset)
                settings.snoozedUntil = nil
                settings.enabled = true
            }
            return "preset=\(preset.name)"
        case .snooze(let minutes):
            return snooze(minutes: minutes)
        case .pauseInMissionControl(let on):
            settings.pauseInMissionControl = on
            return "mc-pause=\(on)"
        case .openSettings(let tab):
            SettingsWindowController.shared.show(tab: tab.flatMap(SettingsTab.init(name:)))
            return "settings opened"
        }
    }
}
