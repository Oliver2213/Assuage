import SwiftUI
import AssuageCore

/// The panel shown by the "Verify Signed Note" Service: it verifies a pasted note
/// against the keys you hold and the note signing keys saved on your contacts, and
/// shows the same signature table as the in-app Verify view — without bringing the
/// main app window forward. Read-only; a Done button closes it.
struct VerifyResultView: View {
    /// Closes the hosting panel (it's an AppKit window, not a SwiftUI sheet).
    let onDone: () -> Void

    @Environment(KeyLibrary.self) private var library
    @Environment(PeopleLibrary.self) private var people
    @State private var bus = ServiceBus.shared

    /// The trust set (your verifier keys + contacts' note signing keys), cached so
    /// it's rebuilt only when a source changes — not on every redraw.
    @State private var trustedKeys: [TrustedKey] = []

    private var note: SignedNote? {
        guard let text = bus.verifyRequest?.text else { return nil }
        return SignedNote(parsing: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note {
                if note.signatures.isEmpty {
                    ContentUnavailableView(
                        "No signatures",
                        systemImage: "questionmark.circle",
                        description: Text("This text isn’t a signed note — it has no signatures to check.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SignatureList(note: note, trustedKeys: trustedKeys, title: "Signatures")
                    signedText(note.text)
                }
            } else {
                ContentUnavailableView("Nothing to verify", systemImage: "signature")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 320)
        .task(id: bus.verifyRequest) {
            // Contacts load lazily; pull them in so the "From" column can attribute
            // a signature to the card that holds the matching key.
            if people.hasAccess, people.people.isEmpty { await people.load() }
            refreshTrustedKeys()
        }
        .onChange(of: people.people) { refreshTrustedKeys() }
        .onChange(of: library.signingKeys) { refreshTrustedKeys() }
    }

    /// The exact text the signatures cover, shown so you can see what was signed.
    private func signedText(_ text: String) -> some View {
        GroupBox("Signed text") {
            ScrollView {
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(maxHeight: 160)
        }
    }

    private func refreshTrustedKeys() {
        trustedKeys = TrustedKey.all(own: library.verifierKeys, contacts: people.people)
    }
}
