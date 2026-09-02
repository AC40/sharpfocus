import Foundation

/// One vocabulary for every remote-control surface: the `sfctl` CLI
/// (distributed notifications) and the `sharpfocus://` URL scheme.
///
///   sfctl enabled 1            sharpfocus://enable | disable | toggle
///   sfctl grayscale 0.8        sharpfocus://set?grayscale=0.8&blur=10&dim=0.2&mode=frontApp
///   sfctl preset "Deep Work"   sharpfocus://preset?name=Deep%20Work  (or /preset/deep-work)
///   sfctl snooze 30            sharpfocus://snooze?minutes=30
///   sfctl settings effect      sharpfocus://settings?tab=effect
enum Command: Equatable {
    case setEnabled(Bool)
    case toggle
    case grayscale(Double)
    case blur(Double)
    case dim(Double)
    case mode(FollowMode)
    case preset(name: String)
    case snooze(minutes: Int)
    case pauseInMissionControl(Bool)
    case openSettings(tab: String?)

    /// Keys the `set` URL accepts — value-only, never side-effecting verbs.
    private static let effectKeys: Set<String> = ["grayscale", "blur", "dim", "mode"]

    /// The single parser; every surface tokenizes into (key, value) and lands here.
    static func parse(key: String, value: String) -> Command? {
        switch key {
        case "enabled": return .setEnabled(bool(value))
        case "toggle": return .toggle
        case "grayscale": return Double(value).map(Command.grayscale)
        case "blur": return Double(value).map(Command.blur)
        case "dim": return Double(value).map(Command.dim)
        case "mode": return FollowMode(rawValue: value).map(Command.mode)
        case "preset": return value.isEmpty ? nil : .preset(name: value)
        case "snooze": return Int(value).map { .snooze(minutes: $0) }
        case "mc-pause": return .pauseInMissionControl(bool(value))
        case "settings": return .openSettings(tab: value.isEmpty ? nil : value)
        default: return nil
        }
    }

    /// `key=value` (or bare `key`) as sent by sfctl.
    static func parse(line: String) -> Command? {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard let key = parts.first else { return nil }
        return parse(key: key, value: parts.count > 1 ? parts[1] : "")
    }

    static func parse(url: URL) -> [Command] {
        guard url.scheme?.lowercased() == "sharpfocus", let host = url.host?.lowercased()
        else { return [] }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String {
            query.first { $0.name == name }?.value ?? ""
        }
        // `sharpfocus://preset/deep-work` — the path doubles as the value.
        let pathValue = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch host {
        case "enable": return [.setEnabled(true)]
        case "disable": return [.setEnabled(false)]
        case "toggle": return [.toggle]
        case "preset":
            let name = value("name").isEmpty ? pathValue : value("name")
            return parse(key: "preset", value: name).map { [$0] } ?? []
        case "snooze":
            return parse(key: "snooze", value: value("minutes")).map { [$0] } ?? []
        case "settings":
            return [.openSettings(tab: value("tab").isEmpty ? (pathValue.isEmpty ? nil : pathValue) : value("tab"))]
        case "set":
            return query.compactMap { item in
                guard effectKeys.contains(item.name), let raw = item.value else { return nil }
                return parse(key: item.name, value: raw)
            }
        default:
            return []
        }
    }

    private static func bool(_ value: String) -> Bool {
        ["1", "true", "yes", "on", ""].contains(value.lowercased())
    }
}

extension String {
    /// "Deep Work" == "deep-work" == "deepwork" for preset lookups.
    var presetLookupKey: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
