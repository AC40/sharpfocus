import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, effect, presets, automation, about
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Mos-style fixed-size, top-tabbed settings panel.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let navigation = SettingsNavigation()

    private init() {
        let host = NSHostingController(rootView: SettingsRootView(navigation: navigation))
        let window = NSWindow(contentViewController: host)
        window.title = "Sharp Focus"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        // Activation is cooperative on macOS 14+; when triggered from a URL or
        // the CLI the system may decline it, so force the window up as well.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

extension Settings {
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            EffectTab().tabItem { Label("Effect", systemImage: "circle.lefthalf.filled") }.tag(SettingsTab.effect)
            PresetsTab().tabItem { Label("Presets", systemImage: "square.stack") }.tag(SettingsTab.presets)
            AutomationTab().tabItem { Label("Automation", systemImage: "clock") }.tag(SettingsTab.automation)
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - Shared controls

private struct CaptionedToggle: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let keys: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
private func points(_ value: Double) -> String { "\(Int(value.rounded())) px" }

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                CaptionedToggle(
                    title: "Launch at login",
                    caption: LoginItem.isSupported
                        ? "Sharp Focus starts when you sign in."
                        : "Available when running from SharpFocus.app.",
                    isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)
                )
                .disabled(!LoginItem.isSupported)
                if LoginItem.requiresApproval {
                    HStack {
                        Text("Needs your approval in System Settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Behavior") {
                CaptionedToggle(
                    title: "Pause in Mission Control",
                    caption: "Hides the effect while Mission Control or App Exposé is open so the animation stays smooth.",
                    isOn: settings.binding(\.pauseInMissionControl))
            }
            Section("Keyboard shortcuts") {
                ShortcutRow(title: "Toggle Sharp Focus", keys: "⌃⌥⌘F")
                ShortcutRow(title: "Pin or unpin the focused window", keys: "⌃⌥⌘P")
            }
            Section("Scripting") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drive Sharp Focus from Raycast, Alfred, Shortcuts or a shell:")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("sfctl preset \"Deep Work\"\nopen \"sharpfocus://set?grayscale=0.8&blur=10\"")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLogin = enabled
            settings.launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}

// MARK: - Effect

private struct EffectTab: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                CaptionedToggle(
                    title: "Enable Sharp Focus",
                    caption: "Everything except the windows you're working in gets filtered.",
                    isOn: settings.binding(\.enabled))
            }
            Section("Effect") {
                if !Backdrop.isAvailable {
                    Label("Grayscale and blur aren't available on this macOS version — only dimming works.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
                LabeledSlider(title: "Grayscale", value: settings.binding(\.grayscale), range: 0...1, format: percent)
                LabeledSlider(title: "Blur", value: settings.binding(\.blurRadius), range: 0...40, format: points)
                LabeledSlider(title: "Dimming", value: settings.binding(\.dimming), range: 0...0.9, format: percent)
            }
            Section("Keep in color") {
                Picker("Follow", selection: settings.binding(\.followMode)) {
                    ForEach(FollowMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                AlwaysAppsList()
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlwaysAppsList: View {
    @ObservedObject var settings = Settings.shared
    @State private var apps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Always in focus").padding(.top, 2)
            Text("These apps stay in color no matter what's active — a music player, for example.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(apps, id: \.processIdentifier) { app in
                        if let bundleID = app.bundleIdentifier {
                            Toggle(isOn: Binding(
                                get: { settings.alwaysApps.contains(bundleID) },
                                set: { _ in settings.toggleAlwaysApp(bundleID) })
                            ) {
                                HStack(spacing: 6) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                    }
                                    Text(app.localizedName ?? bundleID)
                                }
                            }
                        }
                    }
                    ForEach(missingSelected, id: \.self) { bundleID in
                        Toggle(isOn: Binding(
                            get: { true }, set: { _ in settings.toggleAlwaysApp(bundleID) })
                        ) {
                            Text(bundleID).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 110)
        }
        .onAppear(perform: reload)
    }

    private var missingSelected: [String] {
        let running = Set(apps.compactMap(\.bundleIdentifier))
        return settings.alwaysApps.subtracting(running).sorted()
    }

    private func reload() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

// MARK: - Presets

private struct PresetsTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.presets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text(summary(of: preset)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.activePreset?.id == preset.id {
                            Text("Active").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset.id)
                }
            }
            .frame(height: 170)

            HStack(spacing: 8) {
                Button { addPreset() } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Button("Apply") {
                    if let preset = selectedPreset { settings.apply(preset) }
                }
                .disabled(selection == nil)
            }
            .padding(10)

            Divider()

            if let preset = selectedPreset {
                PresetEditor(preset: Binding(
                    get: { settings.presets.first { $0.id == preset.id } ?? preset },
                    set: { updated in
                        var presets = settings.presets
                        if let index = presets.firstIndex(where: { $0.id == updated.id }) {
                            presets[index] = updated
                            settings.presets = presets
                        }
                    }))
            } else {
                Spacer()
                Text("Select a preset to edit it, or add one from your current settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private var selectedPreset: Preset? {
        settings.presets.first { $0.id == selection }
    }

    private func summary(of preset: Preset) -> String {
        var parts = [percent(preset.grayscale) + " gray"]
        if preset.blurRadius > 0.5 { parts.append(points(preset.blurRadius) + " blur") }
        if preset.dimming > 0.005 { parts.append(percent(preset.dimming) + " dim") }
        parts.append(preset.followMode == .focusedWindow ? "focused window" : "active app")
        return parts.joined(separator: " · ")
    }

    private func addPreset() {
        let preset = settings.captureCurrentAsPreset(named: "Preset \(settings.presets.count + 1)")
        selection = preset.id
    }

    private func deleteSelected() {
        guard let selection else { return }
        settings.presets.removeAll { $0.id == selection }
        self.selection = nil
    }
}

private struct PresetEditor: View {
    @Binding var preset: Preset

    var body: some View {
        Form {
            TextField("Name", text: $preset.name)
            LabeledSlider(title: "Grayscale", value: $preset.grayscale, range: 0...1, format: percent)
            LabeledSlider(title: "Blur", value: $preset.blurRadius, range: 0...40, format: points)
            LabeledSlider(title: "Dimming", value: $preset.dimming, range: 0...0.9, format: percent)
            Picker("Follow", selection: $preset.followMode) {
                ForEach(FollowMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation

private struct AutomationTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: UUID?
    @State private var hasFocusAccess = FocusModeMonitor.hasAccess

    var body: some View {
        VStack(spacing: 0) {
            if !hasFocusAccess {
                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("Focus-mode rules need Full Disk Access to read which macOS Focus is active. Time rules work without it.")
                        .font(.footnote)
                    Spacer()
                    Button("Grant…") { FocusModeMonitor.openFullDiskAccessSettings() }
                }
                .padding(10)
                Divider()
            }

            List(selection: $selection) {
                ForEach(settings.automationRules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { newValue in update(rule.id) { $0.isEnabled = newValue } }))
                            .labelsHidden()
                        Text(describe(rule))
                    }
                    .tag(rule.id)
                }
                if settings.automationRules.isEmpty {
                    Text("No rules yet. Add one to switch presets by time of day or macOS Focus mode.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(height: hasFocusAccess ? 150 : 110)

            HStack(spacing: 8) {
                Button { addRule() } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .padding(10)

            Divider()

            if let rule = settings.automationRules.first(where: { $0.id == selection }) {
                RuleEditor(rule: Binding(
                    get: { settings.automationRules.first { $0.id == rule.id } ?? rule },
                    set: { updated in update(updated.id) { $0 = updated } }))
            } else {
                Spacer()
                Text("Select a rule to edit it.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .onAppear { hasFocusAccess = FocusModeMonitor.hasAccess }
    }

    private func update(_ id: UUID, _ change: (inout AutomationRule) -> Void) {
        var rules = settings.automationRules
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[index])
        settings.automationRules = rules
    }

    private func addRule() {
        let action: AutomationRule.Action = settings.presets.first.map { .applyPreset(id: $0.id) } ?? .disable
        let rule = AutomationRule(
            trigger: .timeRange(start: 9 * 60, end: 17 * 60, weekdays: [2, 3, 4, 5, 6]),
            action: action)
        settings.automationRules.append(rule)
        selection = rule.id
    }

    private func deleteSelected() {
        guard let selection else { return }
        settings.automationRules.removeAll { $0.id == selection }
        self.selection = nil
    }

    private func describe(_ rule: AutomationRule) -> String {
        let when: String
        switch rule.trigger {
        case .timeRange(let start, let end, let weekdays):
            when = "\(RuleEditor.weekdaySummary(weekdays)) \(RuleEditor.clock(start))–\(RuleEditor.clock(end))"
        case .focusMode(let name):
            when = "Focus “\(name)”"
        }
        let then: String
        switch rule.action {
        case .applyPreset(let id):
            then = settings.presets.first { $0.id == id }?.name ?? "(missing preset)"
        case .disable:
            then = "turn off"
        }
        return "\(when) → \(then)"
    }
}

private struct RuleEditor: View {
    @Binding var rule: AutomationRule

    private enum TriggerKind: Hashable { case time, focus }

    var body: some View {
        Form {
            Picker("When", selection: triggerKind) {
                Text("Time of day").tag(TriggerKind.time)
                Text("macOS Focus mode").tag(TriggerKind.focus)
            }
            .pickerStyle(.segmented)

            switch rule.trigger {
            case .timeRange(let start, let end, let weekdays):
                DatePicker("From", selection: minutesBinding(start) { s in
                    rule.trigger = .timeRange(start: s, end: end, weekdays: weekdays)
                }, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: minutesBinding(end) { e in
                    rule.trigger = .timeRange(start: start, end: e, weekdays: weekdays)
                }, displayedComponents: .hourAndMinute)
                HStack(spacing: 4) {
                    Text("On").frame(width: 60, alignment: .leading)
                    ForEach(Self.weekdayOrder, id: \.self) { day in
                        Toggle(Self.weekdayNames[day - 1], isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { on in
                                var set = weekdays
                                if on { set.insert(day) } else { set.remove(day) }
                                rule.trigger = .timeRange(start: start, end: end, weekdays: set)
                            }))
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }
            case .focusMode(let name):
                let known = FocusModeMonitor.shared.knownModes
                if known.isEmpty {
                    TextField("Focus mode name", text: Binding(
                        get: { name }, set: { rule.trigger = .focusMode(name: $0) }))
                } else {
                    Picker("Focus mode", selection: Binding(
                        get: { known.contains(name) ? name : known[0] },
                        set: { rule.trigger = .focusMode(name: $0) })
                    ) {
                        ForEach(known, id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Picker("Then", selection: actionSelection) {
                ForEach(Settings.shared.presets) { preset in
                    Text("Apply “\(preset.name)”").tag(preset.id.uuidString)
                }
                Text("Turn Sharp Focus off").tag("disable")
            }
        }
        .formStyle(.grouped)
    }

    private var triggerKind: Binding<TriggerKind> {
        Binding(
            get: {
                if case .focusMode = rule.trigger { return .focus }
                return .time
            },
            set: { kind in
                switch kind {
                case .time:
                    rule.trigger = .timeRange(start: 9 * 60, end: 17 * 60, weekdays: [2, 3, 4, 5, 6])
                case .focus:
                    rule.trigger = .focusMode(name: FocusModeMonitor.shared.knownModes.first ?? "Work")
                }
            })
    }

    private var actionSelection: Binding<String> {
        Binding(
            get: {
                if case .applyPreset(let id) = rule.action { return id.uuidString }
                return "disable"
            },
            set: { value in
                rule.action = UUID(uuidString: value).map { .applyPreset(id: $0) } ?? .disable
            })
    }

    private func minutesBinding(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            })
    }

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]  // Mon…Sun in Calendar numbering
    static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func weekdaySummary(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return weekdayOrder.filter(days.contains).map { weekdayNames[$0 - 1] }.joined(separator: " ")
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "Version \($0)" } ?? "Development build"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Sharp Focus").font(.title2.bold())
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("Only the window you're working in stays in color.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Link(destination: URL(string: "https://github.com/ac40/sharpfocus")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://acrichter.com")!) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/ac40/sharpfocus/issues")!) {
                    Label("Report an issue", systemImage: "ladybug")
                }
            }
            .padding(.top, 6)
            Spacer()
            Text("Made by Aaron Richter. MIT licensed.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Grayscale and blur use an undocumented macOS compositing API (CABackdropLayer). Apple could change it in a future release; if that happens the app falls back to dimming only.")
                .font(.footnote).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer().frame(height: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
