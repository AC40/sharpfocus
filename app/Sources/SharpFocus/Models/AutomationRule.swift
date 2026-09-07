import Foundation

struct AutomationRule: Codable, Identifiable, Equatable {
    enum Trigger: Codable, Equatable {
        case timeRange(start: Int, end: Int, weekdays: Set<Int>)
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
