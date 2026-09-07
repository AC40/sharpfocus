import SwiftUI

struct PermissionsBanner: View {
    @ObservedObject var axMonitor = AccessibilityMonitor.shared
    @State private var hasFDA = FocusModeMonitor.hasAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: axMonitor.isTrusted ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .foregroundStyle(axMonitor.isTrusted ? .green : .orange)
                Text(axMonitor.isTrusted ? "Accessibility granted" : "Accessibility not granted")
                    .font(.callout.weight(.semibold))
                Spacer()
                if axMonitor.isTrusted {
                    Text("Granted ✓").font(.caption).foregroundStyle(.green)
                } else {
                    Button("Grant…") {
                        let trusted = AccessibilityMonitor.check(prompt: true)
                        AccessibilityMonitor.shared.refresh()
                        if !trusted {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                if !AccessibilityMonitor.isTrusted { AccessibilityMonitor.openSettings() }
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }
            Text(axMonitor.isTrusted
                 ? "Pauses only in Mission Control, Exposé, and Launchpad."
                 : "Grant access to detect Mission Control accurately.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !axMonitor.isTrusted {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running from: \(AccessibilityMonitor.runningAppPath)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Text("If System Settings shows it as enabled but you still see this, remove it from the list and add it again from the path above, then relaunch.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Check again") { AccessibilityMonitor.shared.refresh() }
                            .controlSize(.small)
                        Button("Open Settings…") { AccessibilityMonitor.openSettings() }
                            .controlSize(.small)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            HStack(spacing: 8) {
                Button("Onboarding…") { OnboardingWindowController.shared.show() }
                    .controlSize(.small)
                if !hasFDA {
                    Button("Full Disk Access…") { FocusModeMonitor.openFullDiskAccessSettings() }
                        .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .onAppear {
            hasFDA = FocusModeMonitor.hasAccess
            AccessibilityMonitor.shared.startPolling()
            AccessibilityMonitor.shared.refresh()
        }
    }
}
