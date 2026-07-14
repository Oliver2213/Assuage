import SwiftUI
import AssuageCore

/// Verify a signed note: paste it to see its text and each signature's status
/// against the signing keys you hold.
struct VerifyView: View {
    @Environment(AppModel.self) private var model

    private var note: SignedNote { SignedNote(parsing: model.verifyInput) }
    private var hasInput: Bool {
        !model.verifyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var model = model
        // Parse once per body pass rather than on each read of `note` below.
        let note = self.note
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Verify a note.** Paste a signed note to check who signed it. A signature verifies against a signing key you hold; anyone else shows as an unknown signer.")

                MultilineTextField(title: "Signed note", placeholder: "Paste a signed note…", text: $model.verifyInput)

                if hasInput {
                    if note.signatures.isEmpty {
                        Label("This text has no signatures.", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        SignatureList(note: note, verifierKeys: model.verifierKeys, title: "Signatures")
                        CipherOutputView(
                            title: "Signed text",
                            output: .text(note.text),
                            binarySaveName: "note.txt",
                            allowsTextSave: true,
                            textSaveName: "note.txt",
                            font: .callout.monospaced()
                        )
                    }
                }
            }
            .padding(20)
        }
    }
}
