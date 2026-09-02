import Combine
import Foundation

enum FollowMode: String, Codable, CaseIterable {
    /// Only the frontmost window of the active app stays in color.
    case focusedWindow
    /// All windows of the active app stay in color.
    case frontApp

    var displayName: String {
        switch self {
        case .focusedWindow: return "Focused window only"
        case .frontApp: return "All windows of the active app"
        }
    }
}

/// A named bundle of effect settings the user can switch between.
struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var grayscale: Double
    var blurRadius: Double
    var dimming: Double
    var followMode: FollowMode
}

/// "When <trigger>, apply <action>" — evaluated by AutomationEngine.
struct AutomationRule: Codable, Identifiable, Equatable {
    enum Trigger: Codable, Equatable {
        /// Minutes since midnight; weekdays use Calendar numbering (1 = Sunday).
        case timeRange(start: Int, end: Int, weekdays: Set<Int>)
        /// Active macOS Focus mode name, e.g. "Work", "Do Not Disturb".
        case focusMode(name: String)
    }

    enum Action: Codable, Equatable {
        case applyPreset(id: UUID)
        case disable
    }

    var id = UUID()
    var isEnabled = true
    var trigger: Trigger
    var action: Action
}

/// The user's manual effect state, captured before automation takes over.
struct EffectSnapshot: Codable, Equatable {
    var enabled: Bool
    var grayscale: Double
    var blurRadius: Double
    var dimming: Double
    var followMode: FollowMode

    init(_ settings: Settings) {
        enabled = settings.enabled
        grayscale = settings.grayscale
        blurRadius = settings.blurRadius
        dimming = settings.dimming
        followMode = settings.followMode
    }

    func restore(into settings: Settings) {
        settings.batch {
            settings.grayscale = grayscale
            settings.blurRadius = blurRadius
            settings.dimming = dimming
            settings.followMode = followMode
            settings.enabled = enabled
        }
    }
}

/// Persisted while an automation rule is in charge, so a relaunch mid-rule
/// still restores the right manual state afterwards.
struct AutomationState: Codable, Equatable {
    var activeRuleID: UUID
    var action: AutomationRule.Action
    /// What to restore when the rule ends; nil once the user took over.
    var snapshot: EffectSnapshot?
    var userOverrode = false
}

extension Notification.Name {
    /// Posted (coalesced per batch) whenever any setting changes.
    static let sharpFocusSettingsChanged = Notification.Name("SharpFocusSettingsChanged")
}

/// UserDefaults-backed app configuration. Single source of truth for value
/// ranges; every UI and command surface reads them from here.
final class Settings: ObservableObject {
    static let shared = Settings()

    static let grayscaleRange = 0.0...1.0
    static let blurRange = 0.0...40.0
    static let dimmingRange = 0.0...0.9

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let followMode = "followMode"
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
    }

    private var presetsCache: [Preset]?
    private var rulesCache: [AutomationRule]?
    private var stateCache: AutomationState??

    /// Set by AutomationEngine around its own writes so manual edits can be
    /// told apart from automated ones.
    var isAutomationWriting = false

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.followMode: FollowMode.frontApp.rawValue,
            Key.grayscale: 1.0,
            Key.dimming: 0.2,
            Key.blurRadius: 0.0,
            Key.alwaysApps: [String](),
            Key.pauseInMissionControl: true,
        ])
        seedDefaultPresetsIfNeeded()
    }

    // MARK: - Change notification (coalesced)

    private var batchDepth = 0
    private var changePending = false

    /// Groups several writes into one change notification.
    func batch(_ body: () -> Void) {
        batchDepth += 1
        body()
        batchDepth -= 1
        if batchDepth == 0, changePending {
            changePending = false
            notify()
        }
    }

    private func changed() {
        if batchDepth > 0 {
            changePending = true
        } else {
            notify()
        }
    }

    private func notify() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .sharpFocusSettingsChanged, object: self)
    }

    // MARK: - Live effect state

    /// Master switch for the focus overlay.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); manualEdit(); changed() }
    }

    var followMode: FollowMode {
        get { FollowMode(rawValue: defaults.string(forKey: Key.followMode) ?? "") ?? .frontApp }
        set { defaults.set(newValue.rawValue, forKey: Key.followMode); leavePreset(); manualEdit(); changed() }
    }

    /// 0 = no desaturation, 1 = fully black & white.
    var grayscale: Double {
        get { defaults.double(forKey: Key.grayscale) }
        set { defaults.set(Self.grayscaleRange.clamp(newValue), forKey: Key.grayscale); leavePreset(); manualEdit(); changed() }
    }

    /// 0 = no darkening, 0.9 = nearly black.
    var dimming: Double {
        get { defaults.double(forKey: Key.dimming) }
        set { defaults.set(Self.dimmingRange.clamp(newValue), forKey: Key.dimming); leavePreset(); manualEdit(); changed() }
    }

    /// Gaussian blur radius in points applied to non-focused content.
    var blurRadius: Double {
        get { defaults.double(forKey: Key.blurRadius) }
        set { defaults.set(Self.blurRange.clamp(newValue), forKey: Key.blurRadius); leavePreset(); manualEdit(); changed() }
    }

    /// Bundle identifiers of apps whose windows always stay in color.
    var alwaysApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.alwaysApps) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.alwaysApps); changed() }
    }

    func toggleAlwaysApp(_ bundleID: String) {
        var apps = alwaysApps
        if apps.contains(bundleID) { apps.remove(bundleID) } else { apps.insert(bundleID) }
        alwaysApps = apps
    }

    /// True while a snooze is running.
    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    /// What the overlay should actually do right now.
    var isEffectivelyEnabled: Bool { enabled && !isSnoozed }

    /// Hide the overlay while Mission Control / App Exposé is active.
    var pauseInMissionControl: Bool {
        get { defaults.bool(forKey: Key.pauseInMissionControl) }
        set { defaults.set(newValue, forKey: Key.pauseInMissionControl); changed() }
    }

    /// While set, the app is temporarily off and turns itself back on at this
    /// time. Persisted so a relaunch mid-snooze still resumes.
    var snoozedUntil: Date? {
        get { defaults.object(forKey: Key.snoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.snoozedUntil); changed() }
    }

    // MARK: - Presets

    var presets: [Preset] {
        get {
            if let presetsCache { return presetsCache }
            let loaded = decode([Preset].self, forKey: Key.presets) ?? []
            presetsCache = loaded
            return loaded
        }
        set {
            presetsCache = newValue
            encode(newValue, forKey: Key.presets)
            changed()
        }
    }

    /// The preset whose values are currently live; cleared as soon as any
    /// effect value is changed by hand.
    var activePresetID: UUID? {
        get { defaults.string(forKey: Key.activePresetID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.activePresetID); changed() }
    }

    var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        return presets.first { $0.id == id }
    }

    func apply(_ preset: Preset) {
        batch {
            grayscale = preset.grayscale
            blurRadius = preset.blurRadius
            dimming = preset.dimming
            followMode = preset.followMode
            activePresetID = preset.id
        }
    }

    /// Captures the current live settings as a new preset. Without a name, a
    /// unique "Preset N" is generated.
    @discardableResult
    func captureCurrentAsPreset(named name: String? = nil) -> Preset {
        let preset = Preset(
            name: name ?? uniquePresetName(), grayscale: grayscale, blurRadius: blurRadius,
            dimming: dimming, followMode: followMode)
        batch {
            presets.append(preset)
            activePresetID = preset.id
        }
        return preset
    }

    private func uniquePresetName() -> String {
        let taken = Set(presets.map(\.name))
        var index = presets.count + 1
        while taken.contains("Preset \(index)") { index += 1 }
        return "Preset \(index)"
    }

    private func leavePreset() {
        guard defaults.object(forKey: Key.activePresetID) != nil else { return }
        defaults.removeObject(forKey: Key.activePresetID)
    }

    private func seedDefaultPresetsIfNeeded() {
        guard !defaults.bool(forKey: Key.seededDefaultPresets) else { return }
        defaults.set(true, forKey: Key.seededDefaultPresets)
        guard presets.isEmpty else { return }
        presetsCache = nil
        encode([
            Preset(name: "Deep Work", grayscale: 1.0, blurRadius: 12, dimming: 0.3,
                   followMode: .focusedWindow),
            Preset(name: "Soft Focus", grayscale: 0.7, blurRadius: 0, dimming: 0.15,
                   followMode: .frontApp),
            Preset(name: "Monochrome", grayscale: 1.0, blurRadius: 0, dimming: 0.1,
                   followMode: .frontApp),
        ], forKey: Key.presets)
    }

    // MARK: - Automation

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

    /// Bookkeeping for AutomationEngine; doesn't affect the overlay, so it
    /// doesn't post a change notification.
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

    /// A hand-made change while a rule is active hands control back to the
    /// user: the rule stays "consumed" but nothing gets restored when it ends.
    private func manualEdit() {
        guard !isAutomationWriting, var state = automationState, !state.userOverrode else { return }
        state.userOverrode = true
        state.snapshot = nil
        automationState = state
    }

    // MARK: - Codable plumbing

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
