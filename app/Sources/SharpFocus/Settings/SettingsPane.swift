import SwiftUI

struct SettingsPane: View {
    let tab: SettingsTab

    static func height(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .general: return 600
        case .effect: return 620
        case .presets: return 540
        case .automation: return 560
        case .about: return 380
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane()
            case .effect: EffectPane()
            case .presets: PresetsPane()
            case .automation: AutomationPane()
            case .about: AboutPane()
            }
        }
        .frame(width: 520, height: Self.height(for: tab))
    }
}
