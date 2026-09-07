import Foundation

extension Settings {

    var automationRules: [AutomationRule] {
        get {
            if let rulesCache { return rulesCache }
            let loaded = decode([AutomationRule].self, forKey: Key.automationRules) ?? []
            rulesCache = loaded
            return loaded
        }
        set {
            rulesCache = newValue
            encode(newValue, forKey: Key.automationRules)
            changed()
        }
    }

    var automationState: AutomationState? {
        get {
            if let cached = stateCache { return cached }
            let loaded = decode(AutomationState.self, forKey: Key.automationState)
            stateCache = .some(loaded)
            return loaded
        }
        set {
            stateCache = .some(newValue)
            if let newValue { encode(newValue, forKey: Key.automationState) }
            else { defaults.removeObject(forKey: Key.automationState) }
        }
    }

    func manualEdit() {
        guard !isAutomationWriting, var state = automationState, !state.userOverrode else { return }
        state.userOverrode = true
        state.snapshot = nil
        automationState = state
    }
}
