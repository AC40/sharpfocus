import Foundation

enum SettingsTab: String, CaseIterable {
    case general, effect, presets, automation, about

    init?(name: String) {
        self.init(rawValue: name.lowercased())
    }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .effect: return "circle.lefthalf.filled"
        case .presets: return "square.stack"
        case .automation: return "clock"
        case .about: return "info.circle"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
