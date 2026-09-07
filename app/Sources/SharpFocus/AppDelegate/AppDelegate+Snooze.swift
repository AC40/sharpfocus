import AppKit

extension AppDelegate {

    func snooze(minutes: Int) -> String {
        let settings = Settings.shared
        guard settings.enabled else { return "not enabled — nothing to snooze" }
        let clamped = min(max(minutes, 1), 24 * 60)
        settings.snoozedUntil = Date().addingTimeInterval(TimeInterval(clamped * 60))
        NSLog("SharpFocus: snoozed for \(clamped) min")
        return "snoozed \(clamped) min"
    }

    func syncSnoozeTimer() {
        let settings = Settings.shared
        guard let until = settings.snoozedUntil else {
            snoozeTimer?.invalidate()
            snoozeTimer = nil
            return
        }
        if until <= Date() {
            settings.snoozedUntil = nil
            return
        }
        guard snoozeTimer?.fireDate != until else { return }
        snoozeTimer?.invalidate()
        let timer = Timer(fire: until, interval: 0, repeats: false) { _ in
            Settings.shared.snoozedUntil = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    @objc func snoozeSelected(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        _ = snooze(minutes: minutes)
    }

    @objc func resumeFromSnooze() {
        Settings.shared.snoozedUntil = nil
    }
}
