import Foundation

extension Settings {

    var presets: [Preset] {
        get {
            if let presetsCache { return presetsCache }
            let loaded = decode([Preset].self, forKey: Key.presets) ?? []
            presetsCache = loaded
            return loaded
        }
        set {
            presetsCache = newValue
            encode(newValue, forKey: Key.presets)
            changed()
        }
    }

    var activePresetID: UUID? {
        get { defaults.string(forKey: Key.activePresetID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.activePresetID); changed() }
    }

    func apply(_ preset: Preset) {
        batch {
            grayscale = preset.grayscale
            blurRadius = preset.blurRadius
            dimming = preset.dimming
            followMode = preset.followMode
            focusedStaysGrayscale = preset.focusedStaysGrayscale
            activePresetID = preset.id
        }
    }

    @discardableResult
    func captureCurrentAsPreset(named name: String? = nil) -> Preset {
        let preset = Preset(
            name: name ?? uniquePresetName(), grayscale: grayscale, blurRadius: blurRadius,
            dimming: dimming, followMode: followMode,
            focusedStaysGrayscale: focusedStaysGrayscale)
        batch {
            presets.append(preset)
            activePresetID = preset.id
        }
        return preset
    }

    func uniquePresetName() -> String {
        let taken = Set(presets.map(\.name))
        var index = presets.count + 1
        while taken.contains("Preset \(index)") { index += 1 }
        return "Preset \(index)"
    }

    func leavePreset() {
        guard defaults.object(forKey: Key.activePresetID) != nil else { return }
        defaults.removeObject(forKey: Key.activePresetID)
    }

    func seedDefaultPresetsIfNeeded() {
        guard !defaults.bool(forKey: Key.seededDefaultPresets) else { return }
        defaults.set(true, forKey: Key.seededDefaultPresets)
        guard presets.isEmpty else { return }
        presetsCache = nil
        encode([
            Preset(name: "Deep Work", grayscale: 1.0, blurRadius: 12, dimming: 0.3,
                   followMode: .focusedWindow),
            Preset(name: "Soft Focus", grayscale: 0.7, blurRadius: 0, dimming: 0.15,
                   followMode: .frontApp),
            Preset(name: "Monochrome", grayscale: 1.0, blurRadius: 0, dimming: 0.1,
                   followMode: .frontApp),
        ], forKey: Key.presets)
    }
}
