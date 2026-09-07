import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderRow: View {
    let title: String
    @Binding var shortcut: KeyShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(buttonLabel)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(
                            isRecording ? Color.accentColor.opacity(0.2) :
                                Color(nsColor: .quaternaryLabelColor),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isRecording ? Color.accentColor : Color.clear))
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Press a shortcut, or Esc to cancel" : "Click, then press a new shortcut")
                if shortcut != nil, !isRecording {
                    Button { shortcut = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Disable this shortcut")
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var buttonLabel: String {
        if isRecording { return hint ?? "Press shortcut…" }
        return shortcut?.displayString ?? "None"
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape,
               KeyShortcut.carbonModifiers(
                   from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)) == nil {
                stopRecording()
                return nil
            }
            guard let next = KeyShortcut(event: event) else {
                hint = "Include ⌘, ⌥, ⌃ or ⇧"
                return nil
            }
            shortcut = next
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { isRecording = false }
        hint = nil
    }
}
