import Foundation

struct AutomationState: Codable, Equatable {
    var activeRuleID: UUID
    var action: AutomationRule.Action
    var snapshot: EffectSnapshot?
    var userOverrode = false
}

extension Notification.Name {
    static let sharpFocusSettingsChanged = Notification.Name("SharpFocusSettingsChanged")
}
