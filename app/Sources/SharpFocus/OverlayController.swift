import AppKit
import QuartzCore

/// Borderless, click-through window that hosts the filter layers for one screen.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages one overlay window per screen. Each overlay stacks:
///  - a backdrop layer (window-server-side grayscale + blur of what's behind)
///  - a dim layer for optional darkening
/// Both are masked by an even-odd shape with holes cut over the focused windows.
final class OverlayController {
    private struct Overlay {
        let window: OverlayWindow
        let backdropLayer: CALayer?  // nil when the private API is unavailable
        let dimLayer: CALayer
        let maskLayer: CAShapeLayer
        let screenFrame: CGRect  // Cocoa global coords
    }

    private var overlays: [Overlay] = []
    private var currentHoles: [Hole] = []

    private static let holeCornerRadius: CGFloat = 11

    var isActive: Bool { !overlays.isEmpty }

    /// Temporarily hides the overlay (Mission Control) without tearing it
    /// down. `show()` respects this, so nothing can accidentally un-hide it.
    var isSuppressed = false {
        didSet {
            guard isSuppressed != oldValue else { return }
            isSuppressed ? hide() : show()
        }
    }

    func rebuild() {
        tearDown()
        for screen in NSScreen.screens {
            overlays.append(makeOverlay(for: screen))
        }
        applyAppearance()
        applyHoles()
    }

    func tearDown() {
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = []
    }

    func show() {
        guard !isSuppressed else { return }
        overlays.forEach { $0.window.orderFrontRegardless() }
    }

    func hide() {
        overlays.forEach { $0.window.orderOut(nil) }
    }

    /// Holes in global CG coordinates (top-left origin).
    func setHoles(_ holes: [Hole]) {
        currentHoles = holes
        applyHoles()
    }

    /// Re-reads grayscale/blur/dimming and updates the layers.
    func applyAppearance() {
        let settings = Settings.shared
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for overlay in overlays {
            if let backdrop = overlay.backdropLayer {
                var filters: [Any] = []
                if settings.grayscale > 0.001,
                   let saturate = Backdrop.makeFilter("colorSaturate") {
                    saturate.setValue(1.0 - settings.grayscale, forKey: "inputAmount")
                    filters.append(saturate)
                }
                if settings.blurRadius > 0.5,
                   let blur = Backdrop.makeFilter("gaussianBlur") {
                    blur.setValue(settings.blurRadius, forKey: "inputRadius")
                    blur.setValue(true, forKey: "inputHardEdges")
                    filters.append(blur)
                }
                backdrop.filters = filters
                // An unfiltered backdrop is a no-op; hiding it saves compositing.
                backdrop.isHidden = filters.isEmpty
            }
            overlay.dimLayer.opacity = Float(settings.dimming)
        }
        CATransaction.commit()
    }

    // MARK: - Setup

    private func makeOverlay(for screen: NSScreen) -> Overlay {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.displaysWhenScreenProfileChanges = true

        let contentView = window.contentView!
        contentView.wantsLayer = true
        let root = contentView.layer!
        let bounds = CGRect(origin: .zero, size: screen.frame.size)

        var backdropLayer: CALayer?
        if let backdrop = Backdrop.makeLayer() {
            backdrop.frame = bounds
            backdrop.contentsScale = screen.backingScaleFactor
            root.addSublayer(backdrop)
            backdropLayer = backdrop
        }

        let dimLayer = CALayer()
        dimLayer.frame = bounds
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        root.addSublayer(dimLayer)

        let maskLayer = CAShapeLayer()
        maskLayer.frame = bounds
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.cgColor
        root.mask = maskLayer

        return Overlay(
            window: window,
            backdropLayer: backdropLayer,
            dimLayer: dimLayer,
            maskLayer: maskLayer,
            screenFrame: screen.frame
        )
    }

    // MARK: - Mask geometry

    private func applyHoles() {
        // CG global (top-left origin) -> Cocoa global (bottom-left origin).
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?
            .frame.height ?? 0
        let cocoaHoles = currentHoles.map { hole in
            Hole(
                rect: CGRect(x: hole.rect.origin.x, y: primaryHeight - hole.rect.maxY,
                             width: hole.rect.width, height: hole.rect.height),
                rounded: hole.rounded)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for overlay in overlays {
            let path = CGMutablePath()
            let bounds = CGRect(origin: .zero, size: overlay.screenFrame.size)
            path.addRect(bounds)
            for hole in cocoaHoles {
                let local = hole.rect.offsetBy(
                    dx: -overlay.screenFrame.origin.x,
                    dy: -overlay.screenFrame.origin.y
                )
                guard local.intersects(bounds) else { continue }
                if hole.rounded {
                    let radius = min(Self.holeCornerRadius, local.width / 2, local.height / 2)
                    path.addRoundedRect(in: local, cornerWidth: radius, cornerHeight: radius)
                } else {
                    path.addRect(local)
                }
            }
            overlay.maskLayer.path = path
        }
        CATransaction.commit()
    }
}
