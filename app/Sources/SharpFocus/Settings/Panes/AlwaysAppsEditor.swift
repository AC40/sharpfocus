import AppKit
import SwiftUI

struct AlwaysAppsEditor: View {
    @ObservedObject var settings = Settings.shared
    @State private var running: [NSRunningApplication] = []

    var body: some View {
        let selected = settings.alwaysApps.sorted()
        if selected.isEmpty {
            Text("No apps yet.").foregroundStyle(.secondary)
        }
        ForEach(selected, id: \.self) { bundleID in
            HStack(spacing: 8) {
                if let icon = icon(for: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(name(for: bundleID))
                Spacer()
                Button {
                    settings.toggleAlwaysApp(bundleID)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        Menu("Add App…") {
            ForEach(candidates, id: \.processIdentifier) { app in
                Button {
                    if let id = app.bundleIdentifier { settings.toggleAlwaysApp(id) }
                } label: {
                    if let icon = app.icon {
                        Label { Text(app.localizedName ?? "") } icon: { Image(nsImage: icon) }
                    } else {
                        Text(app.localizedName ?? "")
                    }
                }
            }
            if candidates.isEmpty {
                Text("No other apps running")
            }
        }
        .onAppear(perform: reload)
    }

    private var candidates: [NSRunningApplication] {
        running.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return !settings.alwaysApps.contains(id)
        }
    }

    private func reload() {
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func icon(for bundleID: String) -> NSImage? {
        if let app = running.first(where: { $0.bundleIdentifier == bundleID }), let icon = app.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func name(for bundleID: String) -> String {
        if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
            return app.localizedName ?? bundleID
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }
}
