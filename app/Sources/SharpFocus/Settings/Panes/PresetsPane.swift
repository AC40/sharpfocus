import SwiftUI

struct PresetsPane: View {
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
                                               dimming: preset.dimming, mode: preset.followMode,
                                               focusedStaysGrayscale: preset.focusedStaysGrayscale))
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

struct PresetEditor: View {
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
            Toggle("Focused window stays grayscale", isOn: $preset.focusedStaysGrayscale)
        }
        .formStyle(.grouped)
    }
}
