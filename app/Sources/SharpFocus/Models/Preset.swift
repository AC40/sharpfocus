import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var grayscale: Double
    var blurRadius: Double
    var dimming: Double
    var followMode: FollowMode
    var focusedStaysGrayscale = false

    init(id: UUID = UUID(), name: String, grayscale: Double, blurRadius: Double,
         dimming: Double, followMode: FollowMode, focusedStaysGrayscale: Bool = false) {
        self.id = id
        self.name = name
        self.grayscale = grayscale
        self.blurRadius = blurRadius
        self.dimming = dimming
        self.followMode = followMode
        self.focusedStaysGrayscale = focusedStaysGrayscale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        grayscale = try c.decode(Double.self, forKey: .grayscale)
        blurRadius = try c.decode(Double.self, forKey: .blurRadius)
        dimming = try c.decode(Double.self, forKey: .dimming)
        followMode = try c.decode(FollowMode.self, forKey: .followMode)
        focusedStaysGrayscale = try c.decodeIfPresent(Bool.self, forKey: .focusedStaysGrayscale) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(grayscale, forKey: .grayscale)
        try c.encode(blurRadius, forKey: .blurRadius)
        try c.encode(dimming, forKey: .dimming)
        try c.encode(followMode, forKey: .followMode)
        try c.encode(focusedStaysGrayscale, forKey: .focusedStaysGrayscale)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, grayscale, blurRadius, dimming, followMode, focusedStaysGrayscale
    }
}
