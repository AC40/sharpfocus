import AppKit
import SwiftUI

struct CurrentlyPinnedEditor: View {
    @ObservedObject var tracker = FocusTracker.shared
    @State private var highlighter = WindowHighlighter()

    var body: some View {
        let pinned = tracker.allWindows().filter { tracker.pinnedWindowIDs.contains($0.id) }
        if pinned.isEmpty {
            Text("No pinned windows.").foregroundStyle(.secondary)
        }
        ForEach(pinned, id: \.id) { info in
            HStack(spacing: 8) {
                if let icon = icon(for: info.pid) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(info.title).lineLimit(1)
                Spacer()
                Button {
                    tracker.togglePin(info.id)
                } label: {
                    Image(systemName: "pin.slash")
                }
                .buttonStyle(.plain)
                .help("Unpin")
            }
            .onHover { hovering in
                if hovering { highlighter.show(rect: info.bounds) } else { highlighter.hide() }
            }
        }
    }

    private func icon(for pid: pid_t) -> NSImage? {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
