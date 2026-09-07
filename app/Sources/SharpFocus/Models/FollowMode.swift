import Foundation

enum FollowMode: String, Codable, CaseIterable {
    case focusedWindow
    case frontApp

    var displayName: String {
        switch self {
        case .focusedWindow: return "Focused window only"
        case .frontApp: return "All windows of the active app"
        }
    }
}
