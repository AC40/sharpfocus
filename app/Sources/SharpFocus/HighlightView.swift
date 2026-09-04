import AppKit

final class HighlightView: NSView {
    var highlightRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !highlightRect.isEmpty else { return }

        // Fill
        NSColor.systemBlue.withAlphaComponent(0.15).setFill()

        // Border
        NSColor.systemBlue.setStroke()

        let path = NSBezierPath(rect: highlightRect)
        path.lineWidth = 3

        path.fill()
        path.stroke()
    }
}


final class WindowHighlighter {

    private var panel: NSPanel?
    private var highlightView: HighlightView?


    // MARK: - Public

    func show(rect cgRect: CGRect) {
        guard let screen = screenContaining(cgRect) else {
            hide()
            return
        }

        // Convert the Quartz/CG coordinate to AppKit coordinates
        let screenRect = cgRectToAppKit(cgRect)

        // Create overlay if necessary
        if panel == nil {
            createPanel()
        }

        guard let panel, let highlightView else {
            return
        }

        // Put the overlay on the correct screen
        panel.setFrame(screen.frame, display: false)

        // Convert global screen coordinates to panel-local coordinates
        highlightView.highlightRect = CGRect(
            x: screenRect.origin.x - screen.frame.origin.x,
            y: screenRect.origin.y - screen.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )

        panel.orderFrontRegardless()
    }


    func hide() {
        panel?.orderOut(nil)
    }


    // MARK: - Setup

    private func createPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear

        // Don't take focus
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        // Don't interfere with mouse interaction
        panel.ignoresMouseEvents = true

        // Appear above normal windows
        panel.level = .floating

        // Show on all Spaces / fullscreen
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        let view = HighlightView(frame: .zero)
        view.autoresizingMask = [
            .width,
            .height
        ]

        panel.contentView = view

        self.panel = panel
        self.highlightView = view
    }


    // MARK: - Screen handling

    private func screenContaining(_ cgRect: CGRect) -> NSScreen? {
        // Use the center of the window rather than merely `intersects`,
        // which avoids choosing the wrong screen for windows near a boundary.
        let center = CGPoint(
            x: cgRect.midX,
            y: cgRect.midY
        )

        return NSScreen.screens.first { screen in
            screen.frame.contains(center)
        }
    }


    // MARK: - Coordinate conversion

    private func cgRectToAppKit(_ rect: CGRect) -> CGRect {
        /*
         CGWindow coordinates have their origin at the top-left
         of the global display space.

         AppKit coordinates have their origin at the bottom-left.

         Use the global display height to flip Y.
        */

        let displayHeight = CGDisplayPixelsHigh(CGMainDisplayID())

        return CGRect(
            x: rect.origin.x,
            y: CGFloat(displayHeight) - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}