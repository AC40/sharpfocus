import QuartzCore

/// Wrapper around the private CABackdropLayer / CAFilter API.
///
/// A backdrop layer asks the *window server* to sample and filter whatever is
/// composited behind the hosting window (the same mechanism that powers
/// NSVisualEffectView vibrancy). The app never sees any pixels and needs no
/// screen recording permission. Being private API, it can break on macOS
/// updates — availability is probed at runtime; if it's gone, the overlay
/// degrades to dimming-only and says so in the menu.
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

    /// Probed once per launch; the answer can't change while running.
    static let isAvailable: Bool = layerClass != nil && makeFilter("colorSaturate") != nil

    static func makeLayer() -> CALayer? {
        guard let layer = layerClass?.init() else { return nil }
        // Ask the window server to sample content *behind the window* (the
        // flag NSVisualEffectView sets for behind-window blending).
        layer.setValue(true, forKey: "windowServerAware")
        return layer
    }
}
