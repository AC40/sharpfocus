import SwiftUI

struct CaptionedToggle: View {
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
