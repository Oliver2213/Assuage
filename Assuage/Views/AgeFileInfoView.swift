import SwiftUI
import AssuageCore

/// A recipient of an age file we could put a name to — a contact whose published
/// key provably addresses the header, or one of your own identities. Built in the
/// app from `AgeFileInfo.addresses(_:)` matches and handed to `AgeFileInfoView`.
///
/// The Quick Look extension renders the same view but holds no keys or contacts, so
/// it passes none of these — the "Known recipients" section simply doesn't appear.
struct IdentifiedRecipient: Identifiable {
    let id: String
    /// The person: a contact's name, or `"You"` (with the identity's label, if any)
    /// for a held key that isn't published on any contact card.
    let name: String
    /// Which key vouches, e.g. "SSH key (Ed25519)" — so it's clear *how* we know.
    let detail: String
    let systemImage: String
    /// Reveals the backing contact card. `nil` for your own keys (nothing to open)
    /// and always `nil` in the Quick Look extension.
    let onSelect: (() -> Void)?
}

/// A compact, read-only summary of an inspected age file — the same information
/// `age-inspect` reports: armor, recipient types, post-quantum status, and a
/// byte breakdown. Shown when a `.age` file or armored text is loaded to decrypt.
struct AgeFileInfoView: View {
    let info: AgeFileInfo
    /// Whether the user's keys can open this file, judged from the header alone.
    /// `nil` hides the row (e.g. when no identities are loaded to judge against).
    var decryptability: DecryptionCapability? = nil
    /// Recipients we could name — contacts whose keys address the file, plus your
    /// own matching keys. Empty in the Quick Look extension (no keys or contacts).
    var identifiedRecipients: [IdentifiedRecipient] = []

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.doc")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(info.summary)
                        .font(.callout.weight(.medium))
                    if info.isArmored {
                        Text("ASCII-armored")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if let decryptability {
                    Label(decryptability.statusText, systemImage: decryptability.statusIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(decryptability.statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !info.isPassphrase {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(info.recipientCounts.enumerated()), id: \.offset) { _, entry in
                            Label {
                                Text(entry.count > 1 ? "\(entry.count) × \(entry.kind.label)" : entry.kind.label)
                            } icon: {
                                Image(systemName: entry.kind.systemImage)
                            }
                            .font(.caption)
                        }
                    }
                }

                if !identifiedRecipients.isEmpty {
                    knownRecipients
                }

                if info.postQuantum != .unknown {
                    Label(
                        info.postQuantum == .yes ? "Post-quantum secure" : "Not post-quantum secure",
                        systemImage: info.postQuantum == .yes ? "shield.lefthalf.filled" : "shield.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let sizes = info.sizes {
                    Divider()
                    sizeBreakdown(sizes)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    /// Names we could attach to the file's recipients — contacts whose published
    /// keys address it, and your own matching keys. Additive to the count rows
    /// above: only the recipient types that carry a public tag can be named, so
    /// anonymous X25519 recipients still appear only in the counts.
    private var knownRecipients: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Known recipients")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(identifiedRecipients) { recipient in
                IdentifiedRecipientRow(recipient: recipient)
            }
        }
    }

    @ViewBuilder
    private func sizeBreakdown(_ sizes: AgeFileInfo.Sizes) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            sizeRow("Header", sizes.header)
            if info.isArmored { sizeRow("Armor overhead", sizes.armorOverhead) }
            sizeRow("Encryption overhead", sizes.encryptionOverhead)
            sizeRow("Payload", sizes.payload)
            sizeRow("Total", sizes.total, emphasized: true)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func sizeRow(_ label: LocalizedStringKey, _ bytes: Int, emphasized: Bool = false) -> some View {
        GridRow {
            Text(label)
            Text(byteCount(bytes))
                .gridColumnAlignment(.trailing)
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One "Known recipients" row: a person and the key that vouches. Contact rows are
/// buttons that reveal the card (their name is tinted to read as a link); your own
/// keys have nothing to reveal, so they render as plain text. Kept in this file
/// because it ships into the Quick Look extension target alongside `AgeFileInfoView`.
private struct IdentifiedRecipientRow: View {
    let recipient: IdentifiedRecipient

    var body: some View {
        if let onSelect = recipient.onSelect {
            Button(action: onSelect) { label(nameStyle: .tint) }
                .buttonStyle(.plain)
                .help("Reveal “\(recipient.name)” in Contacts")
        } else {
            label(nameStyle: .primary)
        }
    }

    private func label(nameStyle: some ShapeStyle) -> some View {
        Label {
            (Text(recipient.name).foregroundStyle(nameStyle)
                + Text(verbatim: " · ").foregroundStyle(.secondary)
                + Text(recipient.detail).foregroundStyle(.secondary))
                .font(.caption)
        } icon: {
            Image(systemName: recipient.systemImage)
        }
    }
}
