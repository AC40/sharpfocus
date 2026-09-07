import AppKit

final class HighlightView: NSView {
    var highlightRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !highlightRect.isEmpty else { return }
        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
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

    func show(rect cgRect: CGRect) {
        guard let screen = screenContaining(cgRect) else {
            hide()
            return
        }
        let screenRect = cgRectToAppKit(cgRect)
        if panel == nil {
            createPanel()
        }
        guard let panel, let highlightView else { return }
        panel.setFrame(screen.frame, display: false)
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

    private func createPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = HighlightView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view

        self.panel = panel
        self.highlightView = view
    }

    private func screenContaining(_ cgRect: CGRect) -> NSScreen? {
        let center = CGPoint(x: cgRect.midX, y: cgRect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func cgRectToAppKit(_ rect: CGRect) -> CGRect {
        let displayHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        return CGRect(
            x: rect.origin.x,
            y: displayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
