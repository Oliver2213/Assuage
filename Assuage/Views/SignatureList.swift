import SwiftUI
import AssuageCore

/// A titled table of a note's signatures — who signed, whether it verifies against
/// the trusted keys, which trusted key it matched, and its key ID. Shared by Sign and
/// Verify.
///
/// Trust comes from your own signing keys and the note signing keys saved on your
/// contacts. Since a signature's name is self-asserted, the "From" column names the
/// actual source of the matching key — the contact whose card carries it, or you.
struct SignatureList: View {
    let note: SignedNote
    let trustedKeys: [TrustedKey]
    let title: LocalizedStringKey

    private var verifierKeys: [VerifierKey] { trustedKeys.map(\.key) }

    private var rows: [Row] {
        note.verify(with: verifierKeys).map { result in
            Row(signature: result.signature, status: result.status,
                source: trustedKeys.first { $0.key.keyIDBytes == result.signature.keyIDBytes })
        }
    }

    var body: some View {
        let rows = self.rows
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                SignatureSummary(tally: tally(rows))
                signatureTable(rows)
            }
            .padding(4)
        }
    }

    private func signatureTable(_ rows: [Row]) -> some View {
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
                    if let key = row.source?.key {
                        Button("Copy Verifier Key", systemImage: "doc.on.doc") {
                            Pasteboard.copy(key.encoded, sensitive: false)
                        }
                    }
                }
            }
            TableColumn("From") { row in
                if let attribution = row.source?.attribution {
                    Label(attribution, systemImage: row.source?.isFromContact == true ? "person.crop.circle" : "person")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .help("The matching note signing key is saved on this contact’s card.")
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("No matching key")
                }
            }
            TableColumn("Status") { row in
                StatusBadge(status: row.status)
            }
        }
        .frame(minHeight: 80, maxHeight: 200)
        .accessibilityLabel(title)
    }

    /// Count the rows by outcome, for the summary line.
    private func tally(_ rows: [Row]) -> Tally {
        var tally = Tally()
        for row in rows {
            switch row.status {
            case .verified: tally.verified += 1
            case .invalid: tally.invalid += 1
            case .unknownSigner: tally.unknown += 1
            }
        }
        return tally
    }

    struct Row: Identifiable {
        let signature: SignedNote.Signature
        let status: SignedNote.VerificationStatus
        /// The trusted key whose ID matches this signature, if any — the source shown
        /// in the "From" column and used by the Copy Verifier Key action.
        let source: TrustedKey?
        var id: String { signature.id }
    }

    struct Tally { var verified = 0, invalid = 0, unknown = 0 }
}

/// A one-line summary of how a note's signatures came out — the visible headline
/// above the per-signature rows. An invalid signature (a key matched but the text
/// didn't) is called out as a likely edit; unknown signers are noted plainly.
private struct SignatureSummary: View {
    let tally: SignatureList.Tally
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private var total: Int { tally.verified + tally.invalid + tally.unknown }

    var body: some View {
        if total > 0 { content }
    }

    @ViewBuilder private var content: some View {
        if tally.invalid > 0 {
            label(
                tally.invalid == total
                    ? "^[\(tally.invalid) signature](inflect: true) didn’t verify — the text may have changed since it was signed."
                    : "\(tally.invalid) of \(total) signatures didn’t verify — the text may have changed since it was signed.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        } else if tally.unknown == 0 {
            label("^[\(tally.verified) signature](inflect: true) verified.",
                  systemImage: "checkmark.seal.fill", color: .green)
        } else if tally.verified == 0 {
            label("Signed by ^[\(tally.unknown) signer](inflect: true) you don’t recognize.",
                  systemImage: "questionmark.circle", color: .secondary)
        } else {
            label("\(tally.verified) of \(total) signatures verified; the rest are from signers you don’t recognize.",
                  systemImage: "checkmark.seal", color: .green)
        }
    }

    /// Meaning is carried by the icon and text; the color only reinforces it, and is
    /// dropped when the user turns on Differentiate Without Color.
    private func label(_ text: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(differentiateWithoutColor ? .primary : color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The verification outcome for one signature, as a labeled badge. The meaning is
/// carried by the icon *shape* (seal / triangle / circle) and the text — color only
/// reinforces it, and drops out when Differentiate Without Color is on.
private struct StatusBadge: View {
    let status: SignedNote.VerificationStatus
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Label(title, systemImage: icon)
            .foregroundStyle(style)
            .help(help)
    }

    private var title: LocalizedStringKey {
        switch status {
        case .verified: "Verified"
        case .unknownSigner: "Unknown signer"
        case .invalid: "Invalid"
        }
    }

    private var icon: String {
        switch status {
        case .verified: "checkmark.seal.fill"
        case .unknownSigner: "questionmark.circle"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private var help: LocalizedStringKey {
        switch status {
        case .verified(let name): "Verified as “\(name)”."
        case .unknownSigner: "No signing key you hold matches this signature."
        case .invalid: "A key you hold matches, but the signature didn’t verify — the text may have changed."
        }
    }

    private var style: Color {
        if differentiateWithoutColor { return .primary }
        switch status {
        case .verified: return .green
        case .unknownSigner: return .secondary
        case .invalid: return .orange
        }
    }
}
