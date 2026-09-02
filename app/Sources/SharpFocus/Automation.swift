import AppKit

/// Supplies the currently active macOS Focus mode name, if detectable.
protocol FocusModeProviding: AnyObject {
    /// e.g. "Work", "Do Not Disturb"; nil when no Focus is active or the
    /// state can't be read on this system.
    var currentFocusMode: String? { get }
    /// Called (on main) whenever the focus mode may have changed.
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Evaluates automation rules (time ranges and Focus modes) and applies
/// preset/disable actions. When the first rule activates it snapshots the
/// manual state; when no rule matches anymore it restores that snapshot, so
/// automation never permanently clobbers what the user had configured.
final class AutomationEngine {
    private struct Snapshot: Codable {
        var enabled: Bool
        var grayscale: Double
        var blurRadius: Double
        var dimming: Double
        var followMode: FollowMode
    }

    private let focusProvider: FocusModeProviding?
    private var timer: Timer?
    private var activeRuleID: UUID?
    private var snapshot: Snapshot?

    init(focusProvider: FocusModeProviding?) {
        self.focusProvider = focusProvider
        focusProvider?.onChange = { [weak self] in self?.evaluate() }
    }

    func start() {
        guard timer == nil else { return }
        focusProvider?.start()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        focusProvider?.stop()
    }

    func evaluate() {
        let settings = Settings.shared
        let rules = settings.automationRules.filter(\.isEnabled)
        let matching = rules.filter { matches($0.trigger) }

        // Focus-mode rules take precedence over time rules; among equals the
        // later rule in the list wins.
        let winner = matching.last { isFocusTrigger($0.trigger) } ?? matching.last

        guard winner?.id != activeRuleID else { return }

        if let winner {
            if snapshot == nil {
                snapshot = Snapshot(
                    enabled: settings.enabled, grayscale: settings.grayscale,
                    blurRadius: settings.blurRadius, dimming: settings.dimming,
                    followMode: settings.followMode)
            }
            activeRuleID = winner.id
            NSLog("SharpFocus: automation rule matched -> \(describe(winner.action))")
            switch winner.action {
            case .applyPreset(let id):
                if let preset = settings.presets.first(where: { $0.id == id }) {
                    settings.apply(preset)
                    if !settings.enabled { settings.enabled = true }
                }
            case .disable:
                settings.enabled = false
            }
        } else {
            activeRuleID = nil
            if let saved = snapshot {
                snapshot = nil
                NSLog("SharpFocus: automation ended — restoring previous state")
                settings.grayscale = saved.grayscale
                settings.blurRadius = saved.blurRadius
                settings.dimming = saved.dimming
                settings.followMode = saved.followMode
                settings.enabled = saved.enabled
            }
        }
    }

    private func isFocusTrigger(_ trigger: AutomationRule.Trigger) -> Bool {
        if case .focusMode = trigger { return true }
        return false
    }

    private func matches(_ trigger: AutomationRule.Trigger) -> Bool {
        switch trigger {
        case .timeRange(let start, let end, let weekdays):
            let now = Date()
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: now)
            guard weekdays.isEmpty || weekdays.contains(weekday) else { return false }
            let minutes = calendar.component(.hour, from: now) * 60
                + calendar.component(.minute, from: now)
            if start <= end {
                return minutes >= start && minutes < end
            } else {
                // Overnight range, e.g. 22:00-06:00.
                return minutes >= start || minutes < end
            }
        case .focusMode(let name):
            guard let current = focusProvider?.currentFocusMode else { return false }
            return current.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func describe(_ action: AutomationRule.Action) -> String {
        switch action {
        case .applyPreset(let id):
            return "apply preset \(Settings.shared.presets.first { $0.id == id }?.name ?? "?")"
        case .disable:
            return "disable"
        }
    }
}
