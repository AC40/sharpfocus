import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    var isVisible: Bool { window?.isVisible == true }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Sharp Focus"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView())
        window.level = .floating
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        AppActivation.present(window)
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.panelDidClose()
    }

    func showIfNeeded() {
        let settings = Settings.shared
        if settings.hasCompletedOnboarding { return }
        if AccessibilityMonitor.isTrusted {
            settings.hasCompletedOnboarding = true
            return
        }
        show()
    }
}

private struct OnboardingView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var ax = AccessibilityMonitor.shared
    @State private var hasFullDiskAccess = FocusModeMonitor.hasAccess
    @State private var axPollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .padding(.top, 28)
                Text("Welcome to Sharp Focus")
                    .font(.title2.bold())
                Text("Only the window you're working in stays in color.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Two permissions help it work reliably.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            Divider().padding(.top, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    permissionCard(
                        icon: "accessibility",
                        title: "Accessibility",
                        subtitle: "Recommended",
                        description: "Pauses the effect in Mission Control, Exposé, and Launchpad.",
                        isGranted: ax.isTrusted,
                        actionTitle: ax.isTrusted ? "Granted ✓" : "Grant Access",
                        action: grantAccessibility
                    )
                    if !ax.isTrusted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Running from: \(AccessibilityMonitor.runningAppPath)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("If System Settings shows it as enabled but you still see this, remove it from the list and add it again from the path above, then relaunch.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            HStack(spacing: 8) {
                                Button("Check again") { AccessibilityMonitor.shared.refresh() }
                                    .controlSize(.small)
                                Button("Open Settings…") { AccessibilityMonitor.openSettings() }
                                    .controlSize(.small)
                                Button("Reveal in Finder") { NSWorkspace.shared.selectFile(AccessibilityMonitor.runningAppPath, inFileViewerRootedAtPath: "") }
                                    .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                    }

                    permissionCard(
                        icon: "externaldrive.fill.badge.checkmark",
                        title: "Full Disk Access",
                        subtitle: "Optional",
                        description: "Enables Focus mode automation. For example, apply Deep Work when Work focus is on.",
                        isGranted: hasFullDiskAccess,
                        actionTitle: hasFullDiskAccess ? "Granted ✓" : "Open Settings…",
                        action: { FocusModeMonitor.openFullDiskAccessSettings() }
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Skip for now") { completeAndClose() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") { completeAndClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 620)
        .onAppear {
            AccessibilityMonitor.shared.startPolling()
            startPollingFDA()
        }
        .onDisappear {
            axPollTimer?.invalidate()
        }
    }

    private func permissionCard(icon: String, title: String, subtitle: String, description: String, isGranted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isGranted ? .green : .primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(isGranted ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12)))
                            .foregroundStyle(isGranted ? .green : .secondary)
                    }
                    Text(isGranted ? "Ready" : "Not granted yet")
                        .font(.caption)
                        .foregroundStyle(isGranted ? .green : .secondary)
                }
                Spacer()
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isGranted)
            }
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if title == "Accessibility" && !isGranted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Opens a system prompt to grant access. You can also enable it in System Settings → Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private func grantAccessibility() {
        let trusted = AccessibilityMonitor.check(prompt: true)
        AccessibilityMonitor.shared.refresh()
        if !trusted && !AccessibilityMonitor.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AccessibilityMonitor.shared.refresh()
                if !AccessibilityMonitor.isTrusted {
                    AccessibilityMonitor.openSettings()
                }
            }
        }
    }

    private func completeAndClose() {
        Settings.shared.hasCompletedOnboarding = true
        OnboardingWindowController.shared.close()
    }

    private func startPollingFDA() {
        axPollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            let current = FocusModeMonitor.hasAccess
            if current != hasFullDiskAccess { hasFullDiskAccess = current }
        }
        RunLoop.main.add(timer, forMode: .common)
        axPollTimer = timer
    }
}
