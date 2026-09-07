import AppKit
import SwiftUI

final class TitledTabViewController: NSTabViewController {
    override var selectedTabViewItemIndex: Int { didSet { updateTitle() } }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateTitle()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        updateTitle()
    }

    private func updateTitle() {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        let label = tabViewItems[selectedTabViewItemIndex].label
        title = label
        view.window?.title = label
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private let tabs = TitledTabViewController()

    var isVisible: Bool { window?.isVisible == true }

    private init() {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPane(tab: tab))
            host.preferredContentSize = NSSize(width: 520, height: SettingsPane.height(for: tab))
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = Self.toolbarImage(for: tab)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = "Sharp Focus"
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func toolbarImage(for tab: SettingsTab) -> NSImage? {
        // SF Symbols have different intrinsic/optical heights (e.g. square.stack vs
        // gearshape vs circle.lefthalf.filled). Without normalization the toolbar
        // row looks uneven. Force a shared SymbolConfiguration and draw into a
        // fixed-size template canvas so every tab has the same visual height.
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium)
        guard let symbol = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(config) else { return nil }
        let canvasSize = NSSize(width: 30, height: 26)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        let origin = NSPoint(
            x: (canvasSize.width - symbol.size.width) / 2,
            y: (canvasSize.height - symbol.size.height) / 2
        )
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        canvas.unlockFocus()
        canvas.isTemplate = true
        return canvas
    }

    func show(tab: SettingsTab? = nil) {
        guard let window else { return }
        if let tab { tabs.selectedTabViewItemIndex = tab.index }
        if !window.isVisible { window.center() }
        AppActivation.present(window)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.panelDidClose()
    }
}
