import Combine
import Foundation
// Models moved to Models/ folder:
// - FollowMode.swift
// - Preset.swift
// - AutomationRule.swift
// - EffectSnapshot.swift
// - AutomationState.swift
// Presets, Automation, Shortcuts and Persistence moved to Settings/Store/

final class Settings: ObservableObject {
    static let shared = Settings()

    static let grayscaleRange = 0.0...1.0
    static let blurRange = 0.0...40.0
    static let dimmingRange = 0.0...0.9

    let defaults = UserDefaults.standard

    enum Key {
        static let enabled = "enabled"
        static let followMode = "followMode"
        static let focusedStaysGrayscale = "focusedStaysGrayscale"
        static let grayscale = "grayscale"
        static let dimming = "dimming"
        static let blurRadius = "blurRadius"
        static let alwaysApps = "alwaysApps"
        static let pauseInMissionControl = "pauseInMissionControl"
        static let snoozedUntil = "snoozedUntil"
        static let presets = "presets"
        static let activePresetID = "activePresetID"
        static let automationRules = "automationRules"
        static let automationState = "automationState"
        static let seededDefaultPresets = "seededDefaultPresets"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let toggleShortcut = "toggleShortcut"
        static let pinShortcut = "pinShortcut"
    }

    var presetsCache: [Preset]?
    var rulesCache: [AutomationRule]?
    var stateCache: AutomationState??

    var isAutomationWriting = false

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.followMode: FollowMode.frontApp.rawValue,
            Key.grayscale: 1.0,
            Key.dimming: 0.2,
            Key.blurRadius: 0.0,
            Key.alwaysApps: [String](),
            Key.pauseInMissionControl: false,
        ])
        seedDefaultPresetsIfNeeded()
    }

    var batchDepth = 0
    var changePending = false

    func batch(_ body: () -> Void) {
        batchDepth += 1
        body()
        batchDepth -= 1
        if batchDepth == 0, changePending {
            changePending = false
            notify()
        }
    }

    func changed() {
        if batchDepth > 0 { changePending = true } else { notify() }
    }

    func notify() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .sharpFocusSettingsChanged, object: self)
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); manualEdit(); changed() }
    }

    var followMode: FollowMode {
        get { FollowMode(rawValue: defaults.string(forKey: Key.followMode) ?? "") ?? .frontApp }
        set { defaults.set(newValue.rawValue, forKey: Key.followMode); leavePreset(); manualEdit(); changed() }
    }

    var focusedStaysGrayscale: Bool {
        get { defaults.bool(forKey: Key.focusedStaysGrayscale) }
        set { defaults.set(newValue, forKey: Key.focusedStaysGrayscale); leavePreset(); manualEdit(); changed() }
    }

    var grayscale: Double {
        get { defaults.double(forKey: Key.grayscale) }
        set { defaults.set(Self.grayscaleRange.clamp(newValue), forKey: Key.grayscale); leavePreset(); manualEdit(); changed() }
    }

    var dimming: Double {
        get { defaults.double(forKey: Key.dimming) }
        set { defaults.set(Self.dimmingRange.clamp(newValue), forKey: Key.dimming); leavePreset(); manualEdit(); changed() }
    }

    var blurRadius: Double {
        get { defaults.double(forKey: Key.blurRadius) }
        set { defaults.set(Self.blurRange.clamp(newValue), forKey: Key.blurRadius); leavePreset(); manualEdit(); changed() }
    }

    var alwaysApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.alwaysApps) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.alwaysApps); changed() }
    }

    func toggleAlwaysApp(_ bundleID: String) {
        var apps = alwaysApps
        if apps.contains(bundleID) { apps.remove(bundleID) } else { apps.insert(bundleID) }
        alwaysApps = apps
    }

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    var isEffectivelyEnabled: Bool { enabled && !isSnoozed }

    var pauseInMissionControl: Bool {
        get { defaults.bool(forKey: Key.pauseInMissionControl) }
        set { defaults.set(newValue, forKey: Key.pauseInMissionControl); changed() }
    }

    var snoozedUntil: Date? {
        get { defaults.object(forKey: Key.snoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.snoozedUntil); changed() }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding); changed() }
    }
}
