import Foundation

struct EffectSnapshot: Codable, Equatable {
    var enabled: Bool
    var grayscale: Double
    var blurRadius: Double
    var dimming: Double
    var followMode: FollowMode
    var focusedStaysGrayscale: Bool

    init(_ settings: Settings) {
        enabled = settings.enabled
        grayscale = settings.grayscale
        blurRadius = settings.blurRadius
        dimming = settings.dimming
        followMode = settings.followMode
        focusedStaysGrayscale = settings.focusedStaysGrayscale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        grayscale = try c.decode(Double.self, forKey: .grayscale)
        blurRadius = try c.decode(Double.self, forKey: .blurRadius)
        dimming = try c.decode(Double.self, forKey: .dimming)
        followMode = try c.decode(FollowMode.self, forKey: .followMode)
        focusedStaysGrayscale = try c.decodeIfPresent(Bool.self, forKey: .focusedStaysGrayscale) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(grayscale, forKey: .grayscale)
        try c.encode(blurRadius, forKey: .blurRadius)
        try c.encode(dimming, forKey: .dimming)
        try c.encode(followMode, forKey: .followMode)
        try c.encode(focusedStaysGrayscale, forKey: .focusedStaysGrayscale)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, grayscale, blurRadius, dimming, followMode, focusedStaysGrayscale
    }

    func restore(into settings: Settings) {
        settings.batch {
            settings.grayscale = grayscale
            settings.blurRadius = blurRadius
            settings.dimming = dimming
            settings.followMode = followMode
            settings.focusedStaysGrayscale = focusedStaysGrayscale
            settings.enabled = enabled
        }
    }
}
