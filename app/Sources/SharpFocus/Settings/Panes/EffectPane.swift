import SwiftUI

struct EffectPane: View {
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
                    Label("Grayscale and blur are not available on this macOS version. Dimming still works.",
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
                CaptionedToggle(
                    title: "Focused window stays grayscale",
                    caption: "Keeps the focused window grayscale. Pinned windows and Always in Color apps stay in full color.",
                    isOn: settings.binding(\.focusedStaysGrayscale))
            }
            Section {
                AlwaysAppsEditor()
            } header: {
                Text("Always in color")
            } footer: {
                Text("Apps that always stay in color. For example, a music player.")
            }
            Section {
                CurrentlyPinnedEditor()
            } header: {
                Text("Pinned windows")
            } footer: {
                Text("Pinned windows clear when you close them or quit Sharp Focus.")
            }
        }
        .formStyle(.grouped)
    }
}
