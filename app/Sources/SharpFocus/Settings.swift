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
        case .frontApp: return "All windows of active app"
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

extension Notification.Name {
    /// Posted whenever any setting changes. Object is the Settings instance.
    static let sharpFocusSettingsChanged = Notification.Name("SharpFocusSettingsChanged")
}

/// UserDefaults-backed app configuration.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let followMode = "followMode"
        static let grayscale = "grayscale"
        static let dimming = "dimming"
        static let blurRadius = "blurRadius"
        static let alwaysApps = "alwaysApps"
        static let pauseInMissionControl = "pauseInMissionControl"
        static let launchAtLogin = "launchAtLogin"
        static let presets = "presets"
        static let activePresetID = "activePresetID"
        static let automationRules = "automationRules"
        static let seededDefaultPresets = "seededDefaultPresets"
    }

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

    private func notify() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .sharpFocusSettingsChanged, object: self)
    }

    // MARK: - Live effect state

    /// Master switch for the focus overlay.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); notify() }
    }

    var followMode: FollowMode {
        get { FollowMode(rawValue: defaults.string(forKey: Key.followMode) ?? "") ?? .frontApp }
        set { defaults.set(newValue.rawValue, forKey: Key.followMode); notify() }
    }

    /// 0 = no desaturation, 1 = fully black & white.
    var grayscale: Double {
        get { defaults.double(forKey: Key.grayscale) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.grayscale); notify() }
    }

    /// 0 = no darkening, 0.9 = nearly black.
    var dimming: Double {
        get { defaults.double(forKey: Key.dimming) }
        set { defaults.set(min(max(newValue, 0), 0.9), forKey: Key.dimming); notify() }
    }

    /// Gaussian blur radius in points applied to non-focused content.
    var blurRadius: Double {
        get { defaults.double(forKey: Key.blurRadius) }
        set { defaults.set(min(max(newValue, 0), 40), forKey: Key.blurRadius); notify() }
    }

    /// Bundle identifiers of apps whose windows always stay in color.
    var alwaysApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.alwaysApps) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.alwaysApps); notify() }
    }

    func toggleAlwaysApp(_ bundleID: String) {
        var apps = alwaysApps
        if apps.contains(bundleID) { apps.remove(bundleID) } else { apps.insert(bundleID) }
        alwaysApps = apps
    }

    /// Hide the overlay while Mission Control / App Exposé is active.
    var pauseInMissionControl: Bool {
        get { defaults.bool(forKey: Key.pauseInMissionControl) }
        set { defaults.set(newValue, forKey: Key.pauseInMissionControl); notify() }
    }

    /// Mirrors the SMAppService registration; the actual registration happens
    /// in LoginItem so this stays a plain persisted flag.
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin); notify() }
    }

    // MARK: - Presets

    var presets: [Preset] {
        get { decode([Preset].self, forKey: Key.presets) ?? [] }
        set { encode(newValue, forKey: Key.presets); notify() }
    }

    /// The last preset that was applied; nil once any live setting diverges.
    var activePresetID: UUID? {
        get { defaults.string(forKey: Key.activePresetID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.activePresetID); notify() }
    }

    var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        let preset = presets.first { $0.id == id }
        // Only report active while the live values still match.
        guard let preset, matchesLiveSettings(preset) else { return nil }
        return preset
    }

    func apply(_ preset: Preset) {
        defaults.set(min(max(preset.grayscale, 0), 1), forKey: Key.grayscale)
        defaults.set(min(max(preset.dimming, 0), 0.9), forKey: Key.dimming)
        defaults.set(min(max(preset.blurRadius, 0), 40), forKey: Key.blurRadius)
        defaults.set(preset.followMode.rawValue, forKey: Key.followMode)
        defaults.set(preset.id.uuidString, forKey: Key.activePresetID)
        notify()
    }

    /// Captures the current live settings as a new preset.
    func captureCurrentAsPreset(named name: String) -> Preset {
        let preset = Preset(
            name: name, grayscale: grayscale, blurRadius: blurRadius,
            dimming: dimming, followMode: followMode)
        presets.append(preset)
        activePresetID = preset.id
        return preset
    }

    private func matchesLiveSettings(_ preset: Preset) -> Bool {
        abs(preset.grayscale - grayscale) < 0.001
            && abs(preset.blurRadius - blurRadius) < 0.001
            && abs(preset.dimming - dimming) < 0.001
            && preset.followMode == followMode
    }

    private func seedDefaultPresetsIfNeeded() {
        guard !defaults.bool(forKey: Key.seededDefaultPresets) else { return }
        defaults.set(true, forKey: Key.seededDefaultPresets)
        guard presets.isEmpty else { return }
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
        get { decode([AutomationRule].self, forKey: Key.automationRules) ?? [] }
        set { encode(newValue, forKey: Key.automationRules); notify() }
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
