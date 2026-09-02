import Foundation

enum FollowMode: String {
    /// Only the frontmost window of the active app stays in color.
    case focusedWindow
    /// All windows of the active app stay in color.
    case frontApp
}

/// How the de-emphasis effect is rendered.
enum FilterEngine: String, CaseIterable {
    /// Private CABackdropLayer + CAFilter: the window server desaturates/blurs
    /// what's behind the overlay. No screen recording permission, no capture.
    case backdrop
    /// ScreenCaptureKit capture, filtered in-process. Needs Screen Recording.
    case capture
    /// Plain translucent dim layer (HazeOver-style). No permissions, no
    /// grayscale or blur.
    case dim

    var displayName: String {
        switch self {
        case .backdrop: return "Backdrop (window server, private API)"
        case .capture: return "Screen Capture (ScreenCaptureKit)"
        case .dim: return "Dim Only (no permissions)"
        }
    }
}

extension Notification.Name {
    /// Posted whenever any setting changes. Object is the Settings instance.
    static let sharpFocusSettingsChanged = Notification.Name("SharpFocusSettingsChanged")
}

/// UserDefaults-backed app configuration.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let followMode = "followMode"
        static let engine = "engine"
        static let grayscale = "grayscale"
        static let dimming = "dimming"
        static let blurRadius = "blurRadius"
        static let alwaysApps = "alwaysApps"
        static let pauseInMissionControl = "pauseInMissionControl"
    }

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.followMode: FollowMode.frontApp.rawValue,
            Key.engine: FilterEngine.backdrop.rawValue,
            Key.grayscale: 1.0,
            Key.dimming: 0.2,
            Key.blurRadius: 0.0,
            Key.alwaysApps: [String](),
            Key.pauseInMissionControl: true,
        ])
    }

    private func notify() {
        NotificationCenter.default.post(name: .sharpFocusSettingsChanged, object: self)
    }

    /// Master switch for the focus overlay.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); notify() }
    }

    var followMode: FollowMode {
        get { FollowMode(rawValue: defaults.string(forKey: Key.followMode) ?? "") ?? .frontApp }
        set { defaults.set(newValue.rawValue, forKey: Key.followMode); notify() }
    }

    /// The engine the user picked; may not be available at runtime — resolve
    /// with `resolvedEngine()` before use.
    var engine: FilterEngine {
        get { FilterEngine(rawValue: defaults.string(forKey: Key.engine) ?? "") ?? .backdrop }
        set { defaults.set(newValue.rawValue, forKey: Key.engine); notify() }
    }

    /// Gaussian blur radius in points applied to non-focused content
    /// (backdrop and capture engines only).
    var blurRadius: Double {
        get { defaults.double(forKey: Key.blurRadius) }
        set { defaults.set(min(max(newValue, 0), 40), forKey: Key.blurRadius); notify() }
    }

    /// Hide the overlay while Mission Control / App Exposé is active.
    var pauseInMissionControl: Bool {
        get { defaults.bool(forKey: Key.pauseInMissionControl) }
        set { defaults.set(newValue, forKey: Key.pauseInMissionControl); notify() }
    }

    /// 0 = no desaturation, 1 = fully black & white.
    var grayscale: Double {
        get { defaults.double(forKey: Key.grayscale) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.grayscale); notify() }
    }

    /// 0 = no darkening, 1 = fully black.
    var dimming: Double {
        get { defaults.double(forKey: Key.dimming) }
        set { defaults.set(min(max(newValue, 0), 0.9), forKey: Key.dimming); notify() }
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
}
