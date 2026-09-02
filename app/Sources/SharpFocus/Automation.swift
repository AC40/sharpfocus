import AppKit

/// Evaluates automation rules (time ranges and Focus modes) and applies
/// preset/disable actions. When the first rule activates it snapshots the
/// manual state; when no rule matches anymore it restores that snapshot, so
/// automation never permanently clobbers what the user had configured. The
/// snapshot is persisted (Settings.automationState) so this holds across
/// relaunches too.
final class AutomationEngine {
    private let monitor = FocusModeMonitor.shared
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        monitor.onChange = { [weak self] in self?.evaluate() }
        monitor.start()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate()
    }

    func evaluate() {
        let settings = Settings.shared
        let matching = settings.automationRules.filter { $0.isEnabled && matches($0.trigger) }

        // Focus-mode rules take precedence over time rules; among equals the
        // later rule in the list wins.
        let winner = matching.last { isFocusTrigger($0.trigger) } ?? matching.last
        let state = settings.automationState

        if let winner {
            if let state, state.activeRuleID == winner.id,
               state.userOverrode || state.action == winner.action {
                return  // already applied (or the user took over)
            }
            // Chained rules keep the original snapshot; after a user override
            // the current state is the new baseline.
            let snapshot: EffectSnapshot? = (state?.userOverrode == true)
                ? EffectSnapshot(settings)
                : (state?.snapshot ?? EffectSnapshot(settings))
            settings.automationState = AutomationState(
                activeRuleID: winner.id, action: winner.action, snapshot: snapshot)
            NSLog("SharpFocus: automation rule matched -> \(describe(winner.action))")
            automated {
                switch winner.action {
                case .applyPreset(let id):
                    guard let preset = settings.presets.first(where: { $0.id == id }) else { return }
                    settings.batch {
                        settings.apply(preset)
                        settings.enabled = true
                    }
                case .disable:
                    settings.enabled = false
                }
            }
        } else if let state {
            settings.automationState = nil
            if let snapshot = state.snapshot {
                NSLog("SharpFocus: automation ended — restoring previous state")
                automated { snapshot.restore(into: settings) }
            }
        }
    }

    private func automated(_ body: () -> Void) {
        Settings.shared.isAutomationWriting = true
        body()
        Settings.shared.isAutomationWriting = false
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
            guard let current = monitor.currentFocusMode else { return false }
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
