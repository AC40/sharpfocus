import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // Shared state — internal so AppDelegate+* extensions can access
    var statusItem: NSStatusItem!
    let overlays = OverlayController()
    let tracker = FocusTracker.shared
    let automation = AutomationEngine()

    var enableItem: NSMenuItem!
    var pinItem: NSMenuItem!
    var snoozeItem: NSMenuItem!
    let snoozeMenu = NSMenu()
    let presetsMenu = NSMenu()
    var clearPinsItem: NSMenuItem!

    var snoozeTimer: Timer?
    var applyScheduled = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        syncHotKeys()
        setUpCommandChannel()
        AccessibilityMonitor.shared.startPolling()

        tracker.onUpdate = { [weak self] focusHoles, grayHoles in
            self?.overlays.setHoles(focus: focusHoles, gray: grayHoles)
        }
        tracker.onMissionControlChange = { [weak self] active in
            guard let self else { return }
            self.overlays.isSuppressed = active && Settings.shared.pauseInMissionControl
            if Settings.shared.pauseInMissionControl {
                NSLog("SharpFocus: Mission Control \(active ? "entered — overlay paused" : "left — overlay resumed")")
            }
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
        applySettings()
        automation.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            OnboardingWindowController.shared.showIfNeeded()
        }
    }

    @objc private func settingsChanged() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyScheduled = false
            self?.applySettings()
        }
    }

    func applySettings() {
        let settings = Settings.shared
        syncSnoozeTimer()
        syncHotKeys()

        let shouldRun = settings.isEffectivelyEnabled
        if shouldRun, !overlays.isActive {
            overlays.rebuild()
            overlays.show()
            tracker.start()
        } else if !shouldRun, overlays.isActive {
            tracker.stop()
            overlays.tearDown()
        } else if shouldRun {
            overlays.applyAppearance()
            tracker.poll(force: true)
        }
        overlays.isSuppressed = settings.pauseInMissionControl && tracker.missionControlActive

        automation.evaluate()
        refreshMenuState()
    }

    @objc private func screensChanged() {
        guard overlays.isActive else { return }
        overlays.rebuild()
        overlays.show()
        tracker.poll(force: true)
    }
}
