import SwiftUI

/// A passphrase entry field: obscured by default with a reveal toggle. Shared by
/// the Encrypt and Decrypt panels' passphrase modes.
struct PassphraseField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(prompt, text: $text)
                } else {
                    SecureField(prompt, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide passphrase" : "Show passphrase")
            .accessibilityLabel(isRevealed ? "Hide passphrase" : "Show passphrase")
        }
    }
}
