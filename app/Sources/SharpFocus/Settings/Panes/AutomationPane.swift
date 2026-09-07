import SwiftUI

struct AutomationPane: View {
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

struct RuleEditor: View {
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
