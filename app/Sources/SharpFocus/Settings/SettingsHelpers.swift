import SwiftUI

extension Settings {
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
func points(_ value: Double) -> String { "\(Int(value.rounded())) px" }

func effectSummary(grayscale: Double, blur: Double, dimming: Double, mode: FollowMode,
                   focusedStaysGrayscale: Bool = false) -> String {
    var parts = ["\(percent(grayscale)) gray"]
    if blur > 0.5 { parts.append("\(points(blur)) blur") }
    if dimming > 0.005 { parts.append("\(percent(dimming)) dim") }
    parts.append(mode == .focusedWindow ? "focused window" : "active app")
    if focusedStaysGrayscale { parts.append("focus stays gray") }
    return parts.joined(separator: " · ")
}
