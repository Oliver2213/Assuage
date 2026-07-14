import SwiftUI
import AssuageCore

/// A titled table of a note's signatures — who signed, whether it verifies against
/// the trusted keys, and its key ID. Shared by Sign and Verify.
///
/// Trust today comes only from the user's own signing keys, so a note you signed
/// shows as verified and everyone else shows as an unknown signer.
struct SignatureList: View {
    let note: SignedNote
    let verifierKeys: [VerifierKey]
    let title: LocalizedStringKey

    private var rows: [Row] {
        note.verify(with: verifierKeys).map { Row(signature: $0.signature, status: $0.status) }
    }

    var body: some View {
        GroupBox(title) {
            Table(rows) {
                TableColumn("Signer") { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.signature.name)
                        Text("Key ID \(row.signature.keyIDHex)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Copy Key ID", systemImage: "doc.on.doc") {
                            Pasteboard.copy(row.signature.keyIDHex, sensitive: false)
                        }
                        if let key = matchedKey(for: row.signature) {
                            Button("Copy Verifier Key", systemImage: "doc.on.doc") {
                                Pasteboard.copy(key.encoded, sensitive: false)
                            }
                        }
                    }
                }
                TableColumn("Status") { row in
                    StatusBadge(status: row.status)
                }
            }
            .frame(minHeight: 80, maxHeight: 200)
            .accessibilityLabel(title)
            .padding(4)
        }
    }

    /// The trusted key that signed this, if any — for the Copy Verifier Key action.
    private func matchedKey(for signature: SignedNote.Signature) -> VerifierKey? {
        verifierKeys.first { $0.keyIDBytes == signature.keyIDBytes }
    }

    struct Row: Identifiable {
        let signature: SignedNote.Signature
        let status: SignedNote.VerificationStatus
        var id: String { signature.id }
    }
}

/// The verification outcome for one signature, as a labeled, color-coded badge.
private struct StatusBadge: View {
    let status: SignedNote.VerificationStatus

    var body: some View {
        switch status {
        case .verified(let name):
            Label("Verified", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .help("Verified as “\(name)”.")
        case .unknownSigner:
            Label("Unknown signer", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help("No signing key you hold matches this signature.")
        case .invalid:
            Label("Invalid", systemImage: "xmark.seal.fill")
                .foregroundStyle(.red)
                .help("A key you hold matches, but the signature didn’t verify — the text may have changed.")
        }
    }
}
