import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var axMonitor = AccessibilityMonitor.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section { PermissionsBanner() }
            Section {
                CaptionedToggle(
                    title: "Launch at login",
                    caption: LoginItem.isSupported
                        ? "Start Sharp Focus when you sign in."
                        : "Available when running from SharpFocus.app.",
                    isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                .disabled(!LoginItem.isSupported)
                if LoginItem.requiresApproval {
                    LabeledContent("Waiting for approval in System Settings") {
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                    .font(.callout)
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                CaptionedToggle(
                    title: "Pause in Mission Control",
                    caption: axMonitor.isTrusted
                        ? "Pauses in Mission Control, Exposé, and Launchpad."
                        : "Grant Accessibility for accurate detection.",
                    isOn: settings.binding(\.pauseInMissionControl))
            }
            Section {
                ShortcutRecorderRow(
                    title: "Toggle Sharp Focus",
                    shortcut: settings.binding(\.toggleShortcut))
                ShortcutRecorderRow(
                    title: "Pin focused window",
                    shortcut: settings.binding(\.pinShortcut))
                if settings.shortcutsConflict {
                    Label("Both shortcuts are the same — only one action will fire.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Text("Click a shortcut, then press a new combination. Esc cancels, × disables.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.resetShortcutsToDefaults() }
                        .controlSize(.small)
                }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Global shortcuts work from anywhere and need no extra permission.")
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scripting").font(.headline)
                    Text("Raycast, Alfred, Shortcuts and shell scripts can drive Sharp Focus through the bundled sfctl tool or the sharpfocus:// URL scheme.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("sfctl preset \"Deep Work\"\nopen \"sharpfocus://set?grayscale=0.8&blur=10\"")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}
