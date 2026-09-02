import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, effect, presets, automation, about

    init?(name: String) {
        self.init(rawValue: name.lowercased())
    }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .effect: return "circle.lefthalf.filled"
        case .presets: return "square.stack"
        case .automation: return "clock"
        case .about: return "info.circle"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// NSTabViewController doesn't title the window after the selected tab on its
/// own; this one does.
private final class TitledTabViewController: NSTabViewController {
    override var selectedTabViewItemIndex: Int {
        didSet { updateTitle() }
    }

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

/// Preferences-style window: toolbar tabs, fixed width, each pane sized to
/// its content (the classic System Preferences / Mos pattern).
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let tabs = TitledTabViewController()

    private init() {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPane(tab: tab))
            host.preferredContentSize = NSSize(width: 520, height: SettingsPane.height(for: tab))
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = "Sharp Focus"
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(tab: SettingsTab? = nil) {
        guard let window else { return }
        if let tab { tabs.selectedTabViewItemIndex = tab.index }
        if !window.isVisible { window.center() }
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

private struct SettingsPane: View {
    let tab: SettingsTab

    static func height(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .general: return 440
        case .effect: return 560
        case .presets: return 540
        case .automation: return 560
        case .about: return 380
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane()
            case .effect: EffectPane()
            case .presets: PresetsPane()
            case .automation: AutomationPane()
            case .about: AboutPane()
            }
        }
        .frame(width: 520, height: Self.height(for: tab))
    }
}

// MARK: - Shared pieces

private struct CaptionedToggle: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption).font(.callout).foregroundStyle(.secondary)
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
        HStack(spacing: 12) {
            Text(title).frame(width: 76, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let keys: String

    var body: some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
private func points(_ value: Double) -> String { "\(Int(value.rounded())) px" }

private func effectSummary(grayscale: Double, blur: Double, dimming: Double, mode: FollowMode) -> String {
    var parts = ["\(percent(grayscale)) gray"]
    if blur > 0.5 { parts.append("\(points(blur)) blur") }
    if dimming > 0.005 { parts.append("\(percent(dimming)) dim") }
    parts.append(mode == .focusedWindow ? "focused window" : "active app")
    return parts.joined(separator: " · ")
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
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
                    caption: "Lift the effect while Mission Control or App Exposé is open.",
                    isOn: settings.binding(\.pauseInMissionControl))
            }
            Section("Keyboard shortcuts") {
                ShortcutRow(title: "Toggle Sharp Focus", keys: "⌃⌥⌘F")
                ShortcutRow(title: "Pin or unpin the focused window", keys: "⌃⌥⌘P")
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

// MARK: - Effect

private struct EffectPane: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                CaptionedToggle(
                    title: "Sharp Focus",
                    caption: "Everything except the windows you're working in gets filtered.",
                    isOn: settings.binding(\.enabled))
            }
            Section("Effect") {
                if !Backdrop.isAvailable {
                    Label("Grayscale and blur aren't available on this macOS version — only dimming works.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
                LabeledSlider(title: "Grayscale", value: settings.binding(\.grayscale),
                              range: Settings.grayscaleRange, format: percent)
                LabeledSlider(title: "Blur", value: settings.binding(\.blurRadius),
                              range: Settings.blurRange, format: points)
                LabeledSlider(title: "Dimming", value: settings.binding(\.dimming),
                              range: Settings.dimmingRange, format: percent)
            }
            Section("Keep in color") {
                Picker("Follow", selection: settings.binding(\.followMode)) {
                    ForEach(FollowMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                AlwaysAppsEditor()
            } header: {
                Text("Always in color")
            } footer: {
                Text("These apps are never filtered, whatever is active — a music player, for example.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlwaysAppsEditor: View {
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

// MARK: - Presets

private struct PresetsPane: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.presets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text(effectSummary(grayscale: preset.grayscale, blur: preset.blurRadius,
                                               dimming: preset.dimming, mode: preset.followMode))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.activePresetID == preset.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .help("Active")
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(preset.id)
                }
            }
            .frame(height: 190)

            HStack(spacing: 6) {
                ControlGroup {
                    Button { addPreset() } label: { Image(systemName: "plus") }
                        .help("Save current settings as a preset")
                    Button { deleteSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                        .help("Delete preset")
                }
                .controlGroupStyle(.navigation)
                .frame(width: 70)
                Spacer()
                Button("Apply") {
                    if let preset = selectedPreset { settings.apply(preset) }
                }
                .disabled(selection == nil || settings.activePresetID == selection)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

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
                Text("Select a preset to edit it, or press + to save the current settings as one.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
        }
        .onAppear(perform: selectDefault)
    }

    private var selectedPreset: Preset? {
        settings.presets.first { $0.id == selection }
    }

    private func selectDefault() {
        if selection == nil { selection = settings.activePresetID ?? settings.presets.first?.id }
    }

    private func addPreset() {
        selection = settings.captureCurrentAsPreset().id
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
            LabeledSlider(title: "Grayscale", value: $preset.grayscale,
                          range: Settings.grayscaleRange, format: percent)
            LabeledSlider(title: "Blur", value: $preset.blurRadius,
                          range: Settings.blurRange, format: points)
            LabeledSlider(title: "Dimming", value: $preset.dimming,
                          range: Settings.dimmingRange, format: percent)
            Picker("Keep in color", selection: $preset.followMode) {
                ForEach(FollowMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation

private struct AutomationPane: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: UUID?
    @State private var hasFocusAccess = FocusModeMonitor.hasAccess

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.automationRules) { rule in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { newValue in update(rule.id) { $0.isEnabled = newValue } }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        Text(describe(rule))
                            .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                        Spacer()
                        if settings.automationState?.activeRuleID == rule.id {
                            Text("Active").font(.caption).foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(rule.id)
                }
                if settings.automationRules.isEmpty {
                    Text("No rules yet. Rules switch presets by time of day or by macOS Focus mode.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(height: 170)

            HStack(spacing: 6) {
                ControlGroup {
                    Button { addRule() } label: { Image(systemName: "plus") }
                    Button { deleteSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                }
                .controlGroupStyle(.navigation)
                .frame(width: 70)
                Spacer()
                if !hasFocusAccess {
                    Text("Focus-mode rules need Full Disk Access.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Grant…") { FocusModeMonitor.openFullDiskAccessSettings() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if let rule = settings.automationRules.first(where: { $0.id == selection }) {
                RuleEditor(rule: Binding(
                    get: { settings.automationRules.first { $0.id == rule.id } ?? rule },
                    set: { updated in update(updated.id) { $0 = updated } }))
            } else {
                Spacer()
                Text(settings.automationRules.isEmpty
                     ? "Press + to add a rule."
                     : "Select a rule to edit it.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .onAppear {
            hasFocusAccess = FocusModeMonitor.hasAccess
            if selection == nil { selection = settings.automationRules.first?.id }
        }
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
            when = "\(Weekdays.summary(weekdays)), \(Clock.string(start))–\(Clock.string(end))"
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
                DatePicker("From", selection: Clock.binding(start) { s in
                    rule.trigger = .timeRange(start: s, end: end, weekdays: weekdays)
                }, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: Clock.binding(end) { e in
                    rule.trigger = .timeRange(start: start, end: e, weekdays: weekdays)
                }, displayedComponents: .hourAndMinute)
                LabeledContent("On") {
                    HStack(spacing: 3) {
                        ForEach(Weekdays.order, id: \.self) { day in
                            Toggle(Weekdays.shortName(day), isOn: Binding(
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
                }
            case .focusMode(let name):
                let known = FocusModeMonitor.shared.knownModes
                if known.isEmpty {
                    TextField("Focus mode name", text: Binding(
                        get: { name }, set: { rule.trigger = .focusMode(name: $0) }))
                } else {
                    // Keep whatever the rule says even if it's not in the list.
                    let options = known.contains(name) ? known : known + [name]
                    Picker("Focus mode", selection: Binding(
                        get: { name }, set: { rule.trigger = .focusMode(name: $0) })
                    ) {
                        ForEach(options, id: \.self) { Text($0).tag($0) }
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
}

/// Locale-aware helpers for the rule editor and summaries.
private enum Clock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func string(_ minutes: Int) -> String {
        formatter.string(from: date(minutes: minutes))
    }

    static func binding(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { date(minutes: minutes) },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            })
    }
}

private enum Weekdays {
    /// Calendar weekday numbers in the user's first-weekday order.
    static var order: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func shortName(_ day: Int) -> String {
        Calendar.current.veryShortWeekdaySymbols[day - 1]
    }

    static func summary(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return order.filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: " ")
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "Version \($0)" } ?? "Development build"
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Sharp Focus").font(.title2.bold())
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("Only the window you're working in stays in color.")
                .font(.body).foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 22) {
                Link("GitHub", destination: URL(string: "https://github.com/ac40/sharpfocus")!)
                Link("Website", destination: URL(string: "https://acrichter.com")!)
                Link("Report an issue", destination: URL(string: "https://github.com/ac40/sharpfocus/issues")!)
            }
            .font(.callout)
            .padding(.top, 10)
            Spacer()
            Text("Made by Aaron Richter · MIT License")
                .font(.callout).foregroundStyle(.secondary)
            Text("Grayscale and blur rely on an undocumented macOS compositing API. If a future release changes it, Sharp Focus falls back to dimming only.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
