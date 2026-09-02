import QuartzCore

/// Wrapper around the private CABackdropLayer / CAFilter API.
///
/// A backdrop layer asks the *window server* to sample and filter whatever is
/// composited behind the hosting window (the same mechanism that powers
/// NSVisualEffectView vibrancy). The app never sees any pixels and needs no
/// screen recording permission. Being private API, it can break on macOS
/// updates — availability is probed at runtime and the app falls back to the
/// capture engine if anything is missing.
enum Backdrop {
    static let layerClass: CALayer.Type? = NSClassFromString("CABackdropLayer") as? CALayer.Type

    private static let filterClass: AnyObject? = NSClassFromString("CAFilter")
    private static let filterSelector = NSSelectorFromString("filterWithType:")

    /// Known CAFilter types used here: "colorSaturate" (inputAmount),
    /// "gaussianBlur" (inputRadius, inputHardEdges).
    static func makeFilter(_ type: String) -> NSObject? {
        guard let filterClass, filterClass.responds(to: filterSelector) else { return nil }
        return filterClass.perform(filterSelector, with: type)?.takeUnretainedValue() as? NSObject
    }

    static var isAvailable: Bool {
        layerClass != nil && makeFilter("colorSaturate") != nil
    }

    static func makeLayer() -> CALayer? {
        guard let layer = layerClass?.init() else { return nil }
        // Ask the window server to sample content *behind the window* (the
        // flag NSVisualEffectView sets for behind-window blending).
        layer.setValue(true, forKey: "windowServerAware")
        return layer
    }
}

extension FilterEngine {
    /// Resolves the preferred engine to one that can actually run right now.
    /// Fallback chain: backdrop -> capture -> dim.
    static func resolve(_ preferred: FilterEngine) -> FilterEngine {
        switch preferred {
        case .backdrop:
            return Backdrop.isAvailable ? .backdrop : resolve(.capture)
        case .capture:
            return CaptureEngine.hasScreenRecordingPermission ? .capture : .dim
        case .dim:
            return .dim
        }
    }

    static var availability: [FilterEngine: Bool] {
        [
            .backdrop: Backdrop.isAvailable,
            .capture: CaptureEngine.hasScreenRecordingPermission,
            .dim: true,
        ]
    }
}
