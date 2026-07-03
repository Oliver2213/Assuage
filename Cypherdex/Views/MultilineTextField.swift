import SwiftUI

/// A titled, self-sizing multi-line text field with a placeholder.
struct MultilineTextField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var font: Font = .body.monospaced()

    var body: some View {
        GroupBox(title) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .lineLimit(5...)
        }
    }
}
