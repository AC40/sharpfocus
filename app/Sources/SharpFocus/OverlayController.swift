import AppKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    private struct Overlay {
        let window: OverlayWindow
        let grayBackdropLayer: CALayer?
        let blurBackdropLayer: CALayer?
        let dimLayer: CALayer
        let grayMask: CAShapeLayer
        let blurMask: CAShapeLayer
        let dimMask: CAShapeLayer
        let screenFrame: CGRect
    }

    private var overlays: [Overlay] = []
    private var currentFocusHoles: [Hole] = []
    private var currentGrayHoles: [Hole] = []

    private static let holeCornerRadius: CGFloat = 11

    var isActive: Bool { !overlays.isEmpty }

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

    func setHoles(focus focusHoles: [Hole], gray grayHoles: [Hole]) {
        currentFocusHoles = focusHoles
        currentGrayHoles = grayHoles
        applyHoles()
    }

    func applyAppearance() {
        let settings = Settings.shared
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for overlay in overlays {
            if let gray = overlay.grayBackdropLayer {
                var filters: [Any] = []
                if settings.grayscale > 0.001,
                   let saturate = Backdrop.makeFilter("colorSaturate") {
                    saturate.setValue(1.0 - settings.grayscale, forKey: "inputAmount")
                    filters.append(saturate)
                }
                gray.filters = filters
                gray.isHidden = filters.isEmpty
            }
            if let blur = overlay.blurBackdropLayer {
                var filters: [Any] = []
                if settings.blurRadius > 0.5,
                   let blurFilter = Backdrop.makeFilter("gaussianBlur") {
                    blurFilter.setValue(settings.blurRadius, forKey: "inputRadius")
                    blurFilter.setValue(true, forKey: "inputHardEdges")
                    filters.append(blurFilter)
                }
                blur.filters = filters
                blur.isHidden = filters.isEmpty
            }
            overlay.dimLayer.opacity = Float(settings.dimming)
        }
        CATransaction.commit()
    }

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

        var grayBackdropLayer: CALayer?
        var blurBackdropLayer: CALayer?
        let grayMask = Self.makeMask(frame: bounds)
        let blurMask = Self.makeMask(frame: bounds)
        let dimMask = Self.makeMask(frame: bounds)
        if let gray = Backdrop.makeLayer() {
            gray.frame = bounds
            gray.contentsScale = screen.backingScaleFactor
            gray.mask = grayMask
            root.addSublayer(gray)
            grayBackdropLayer = gray
        }
        if let blur = Backdrop.makeLayer() {
            blur.frame = bounds
            blur.contentsScale = screen.backingScaleFactor
            blur.mask = blurMask
            root.addSublayer(blur)
            blurBackdropLayer = blur
        }

        let dimLayer = CALayer()
        dimLayer.frame = bounds
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        dimLayer.mask = dimMask
        root.addSublayer(dimLayer)

        return Overlay(
            window: window,
            grayBackdropLayer: grayBackdropLayer,
            blurBackdropLayer: blurBackdropLayer,
            dimLayer: dimLayer,
            grayMask: grayMask,
            blurMask: blurMask,
            dimMask: dimMask,
            screenFrame: screen.frame
        )
    }

    private static func makeMask(frame: CGRect) -> CAShapeLayer {
        let mask = CAShapeLayer()
        mask.frame = frame
        mask.fillRule = .evenOdd
        mask.fillColor = NSColor.black.cgColor
        return mask
    }

    private func applyHoles() {
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?
            .frame.height ?? 0
        let cocoaFocusHoles = currentFocusHoles.map { Self.toCocoa($0, primaryHeight: primaryHeight) }
        let cocoaGrayHoles = currentGrayHoles.map { Self.toCocoa($0, primaryHeight: primaryHeight) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for overlay in overlays {
            let bounds = CGRect(origin: .zero, size: overlay.screenFrame.size)
            overlay.blurMask.path = Self.maskPath(bounds: bounds, screenFrame: overlay.screenFrame,
                                                  holes: cocoaFocusHoles)
            overlay.dimMask.path = Self.maskPath(bounds: bounds, screenFrame: overlay.screenFrame,
                                                 holes: cocoaFocusHoles)
            overlay.grayMask.path = Self.maskPath(bounds: bounds, screenFrame: overlay.screenFrame,
                                                  holes: cocoaGrayHoles)
        }
        CATransaction.commit()
    }

    private static func toCocoa(_ hole: Hole, primaryHeight: CGFloat) -> Hole {
        Hole(
            rect: CGRect(x: hole.rect.origin.x, y: primaryHeight - hole.rect.maxY,
                         width: hole.rect.width, height: hole.rect.height),
            rounded: hole.rounded)
    }

    private static func maskPath(bounds: CGRect, screenFrame: CGRect, holes: [Hole]) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        for hole in holes {
            let local = hole.rect.offsetBy(
                dx: -screenFrame.origin.x,
                dy: -screenFrame.origin.y
            )
            guard local.intersects(bounds) else { continue }
            if hole.rounded {
                let radius = min(Self.holeCornerRadius, local.width / 2, local.height / 2)
                path.addRoundedRect(in: local, cornerWidth: radius, cornerHeight: radius)
            } else {
                path.addRect(local)
            }
        }
        return path
    }
}
