import Foundation

/// One vocabulary for every remote-control surface: the `sfctl` CLI
/// (distributed notifications) and the `sharpfocus://` URL scheme.
///
///   sfctl enabled 1        sharpfocus://enable | disable | toggle
///   sfctl grayscale 0.8    sharpfocus://set?grayscale=0.8&blur=10&dim=0.2&mode=frontApp
///   sfctl preset "Deep Work"   sharpfocus://preset?name=Deep%20Work
///   sfctl snooze 30        sharpfocus://snooze?minutes=30
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
    case openSettings

    static func parse(key: String, value: String) -> Command? {
        switch key {
        case "enabled": return .setEnabled(Self.bool(value))
        case "toggle": return .toggle
        case "grayscale": return Double(value).map(Command.grayscale)
        case "blur": return Double(value).map(Command.blur)
        case "dim": return Double(value).map(Command.dim)
        case "mode": return FollowMode(rawValue: value).map(Command.mode)
        case "preset": return .preset(name: value)
        case "snooze": return Int(value).map { .snooze(minutes: $0) }
        case "mc-pause": return .pauseInMissionControl(Self.bool(value))
        case "settings": return .openSettings
        default: return nil
        }
    }

    /// `key=value` form used by sfctl.
    static func parse(line: String) -> Command? {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            switch parts.first {
            case "toggle": return .toggle
            case "settings": return .openSettings
            default: return nil
            }
        }
        return parse(key: parts[0], value: parts[1])
    }

    static func parse(url: URL) -> [Command] {
        guard url.scheme?.lowercased() == "sharpfocus" else { return [] }
        let host = (url.host ?? "").lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch host {
        case "enable": return [.setEnabled(true)]
        case "disable": return [.setEnabled(false)]
        case "toggle": return [.toggle]
        case "settings": return [.openSettings]
        case "preset": return value("name").map { [.preset(name: $0)] } ?? []
        case "snooze": return value("minutes").flatMap(Int.init).map { [.snooze(minutes: $0)] } ?? []
        case "set":
            return query.compactMap { item in
                item.value.flatMap { parse(key: item.name, value: $0) }
            }
        default: return []
        }
    }

    private static func bool(_ value: String) -> Bool {
        ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}
