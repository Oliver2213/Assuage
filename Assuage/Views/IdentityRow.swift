import SwiftUI
import AssuageCore

/// A detailed row for one identity, with inline actions for copying, exporting,
/// editing, and deleting it. Multi-select actions live in the list's context menu
/// (see `KeysView`).
struct IdentityRow: View {
    @Environment(AppModel.self) private var model
    let identity: AgeIdentity
    /// Ask the parent to confirm and perform deletion.
    let onRequestDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: identity.sourceIcon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(identity.displayName)
                    .font(.headline)
                Spacer()
                Text(identity.kindDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            LabeledContent("Public key") {
                PublicKeyText(recipient: identity.recipient)
            }
            LabeledContent("Created", value: identity.created.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Storage", value: identity.sourceDescription)
            if let accessControl = identity.accessControl {
                LabeledContent("Requires", value: accessControl.displayName)
            }

            HStack(spacing: 8) {
                Button("Copy Recipient", systemImage: "doc.on.doc") { copyRecipient() }
                Button("Export Public Key…", systemImage: "square.and.arrow.up") { model.exportRecipients(for: [identity]) }
                Button("Export Identity…", systemImage: "key") { model.exportingKeys = ExportRequest(identities: [identity]) }
                Spacer()
                Button("Edit", systemImage: "pencil") { model.editingKey = identity }
                    .labelStyle(.iconOnly)
                Button("Delete", systemImage: "trash", role: .destructive, action: onRequestDelete)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    // MARK: Actions

    private func copyRecipient() {
        // A public key — only protected when the user opts to protect all copies.
        Pasteboard.copy(identity.recipient.encoding, sensitive: false)
    }
}
