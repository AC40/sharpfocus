import QuartzCore

enum Backdrop {
    static let layerClass: CALayer.Type? = NSClassFromString("CABackdropLayer") as? CALayer.Type

    private static let filterClass: AnyObject? = NSClassFromString("CAFilter")
    private static let filterSelector = NSSelectorFromString("filterWithType:")

    static func makeFilter(_ type: String) -> NSObject? {
        guard let filterClass, filterClass.responds(to: filterSelector) else { return nil }
        return filterClass.perform(filterSelector, with: type)?.takeUnretainedValue() as? NSObject
    }

    static let isAvailable: Bool = layerClass != nil && makeFilter("colorSaturate") != nil

    static func makeLayer() -> CALayer? {
        guard let layer = layerClass?.init() else { return nil }
        layer.setValue(true, forKey: "windowServerAware")
        return layer
    }
}
