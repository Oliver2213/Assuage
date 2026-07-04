import SwiftUI
import CypherdexCore

/// A detailed row for one identity, with visible actions, a matching context
/// menu, and shortcuts to compose an encrypt/decrypt with this key.
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
                Text(identity.recipient.encoding)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LabeledContent("Created", value: identity.created.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Storage", value: identity.sourceDescription)
            if let accessControl = identity.accessControl {
                LabeledContent("Requires", value: accessControl.displayName)
            }

            HStack(spacing: 8) {
                Button("Copy Recipient", systemImage: "doc.on.doc") { copyRecipient() }
                Button("Export Public Key…", systemImage: "square.and.arrow.up") { exportPublicKey() }
                Button("Export Identity…", systemImage: "key") { model.exportingKeys = ExportRequest(identities: [identity]) }
                Spacer()
                Button("Edit", systemImage: "pencil") { model.editingKey = identity }
                    .labelStyle(.iconOnly)
                Button("Delete", systemImage: "trash", role: .destructive, action: onRequestDelete)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .contextMenu {
            Button("Encrypt to This Recipient", systemImage: "lock") {
                model.composeEncrypt(to: identity)
            }
            Button("Decrypt with This Identity", systemImage: "lock.open") {
                model.composeDecrypt(with: identity)
            }
            Divider()
            Button("Copy Recipient", systemImage: "doc.on.doc") { copyRecipient() }
            Button("Export Public Key…", systemImage: "square.and.arrow.up") { exportPublicKey() }
            Button("Export Identity…", systemImage: "key") { model.exportingKeys = ExportRequest(identities: [identity]) }
            Divider()
            Button("Edit…", systemImage: "pencil") { model.editingKey = identity }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onRequestDelete)
        }
    }

    // MARK: Actions

    private var fileBase: String {
        identity.displayName.replacingOccurrences(of: " ", with: "-")
    }

    private func copyRecipient() {
        // A public key — only protected when the user opts to protect all copies.
        Pasteboard.copy(identity.recipient.encoding, sensitive: false)
    }

    private func exportPublicKey() {
        SavePanel.save(text: identity.publicKeyFile(), suggestedName: "\(fileBase).pub")
    }
}
