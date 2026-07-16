import SwiftUI
import AssuageCore

/// Verify a signed note: paste it to see its text and each signature's status
/// against the keys you trust — your own signing keys, and the note signing keys
/// saved on your contacts. Signers you don't have a key for show as unknown.
struct VerifyView: View {
    @Environment(AppModel.self) private var model
    @Environment(PeopleLibrary.self) private var people

    @State private var showContactPicker = false
    /// A contact chosen in the picker, held until the picker closes so its editor can
    /// open cleanly after (rather than stacking one sheet directly on another).
    @State private var pendingContact: Person?
    /// The contact whose key editor is open.
    @State private var editingContact: Person?

    /// Everyone we'll verify against: the user's own verifier keys plus every note
    /// signing key saved on a contact, each tagged with where it came from. Cached
    /// rather than recomputed per body pass, since it changes only when your keys or
    /// contacts do — not on every keystroke in the note field — and rebuilding it walks
    /// every contact. Refreshed when either source changes, so a key saved through the
    /// editor takes effect right away.
    @State private var trustedKeys: [TrustedKey] = []

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
                InfoBanner("**Verify a note.** Paste a signed note to check who signed it. A signature verifies against a signing key you hold or a note signing key saved on a contact; anyone else shows as an unknown signer.")

                MultilineTextField(title: "Signed note", placeholder: "Paste a signed note…", text: $model.verifyInput)

                if hasInput {
                    if note.signatures.isEmpty {
                        Label("This text has no signatures.", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        SignatureList(note: note, trustedKeys: trustedKeys, title: "Signatures")
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

                Button("Add Note Signing Key to Contact…", systemImage: "person.badge.plus") {
                    showContactPicker = true
                }
                .help("Save a note signing key onto a contact so their signed notes verify as them")
            }
            .padding(20)
        }
        // Pick a contact, then — once that sheet has closed — open its key editor, where
        // the note signing key is pasted or fetched like any other. Saving writes it to
        // the card, and `refreshTrustedKeys` picks it up when `people.people` changes.
        .sheet(isPresented: $showContactPicker, onDismiss: openPendingEditor) {
            ContactPickerSheet(purpose: .noteSigner) { pendingContact = $0 }
        }
        .sheet(item: $editingContact, content: EditPersonSheet.init)
        .task { refreshTrustedKeys() }
        .onChange(of: people.people) { refreshTrustedKeys() }
        .onChange(of: model.verifierKeys) { refreshTrustedKeys() }
    }

    private func refreshTrustedKeys() {
        trustedKeys = TrustedKey.all(own: model.verifierKeys, contacts: people.people)
    }

    private func openPendingEditor() {
        guard let contact = pendingContact else { return }
        pendingContact = nil
        editingContact = contact
    }
}
