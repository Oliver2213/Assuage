import SwiftUI
import AppKit
import CypherdexCore

/// A detailed row for one identity, with visible actions, a matching context
/// menu, and shortcuts to compose an encrypt/decrypt with this key.
struct IdentityRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKeys.exportAuthPolicy) private var exportAuthPolicy: ExportAuthPolicy = .always
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
                Button("Export Identity…", systemImage: "key") { exportIdentity() }
                Spacer()
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
            Button("Export Identity…", systemImage: "key") { exportIdentity() }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onRequestDelete)
        }
    }

    // MARK: Actions

    private var fileBase: String {
        identity.displayName.replacingOccurrences(of: " ", with: "-")
    }

    private func copyRecipient() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(identity.recipient.encoding, forType: .string)
    }

    private func exportPublicKey() {
        SavePanel.save(text: identity.publicKeyFile(), suggestedName: "\(fileBase).pub")
    }

    private func exportIdentity() {
        Task {
            guard await authorizeExportIfNeeded() else { return }
            SavePanel.save(text: identity.ageFormatted(), suggestedName: "\(fileBase).txt")
        }
    }

    /// Apply the export-auth preference. Secure Enclave exports are device-locked
    /// blobs, so "only keychain keys" skips them; keychain secrets always gate.
    private func authorizeExportIfNeeded() async -> Bool {
        let needsAuth: Bool
        switch exportAuthPolicy {
        case .always: needsAuth = true
        case .keychainOnly: needsAuth = identity.source != .secureEnclave
        case .never: needsAuth = false
        }
        guard needsAuth else { return true }
        return await Authentication.authorize(
            reason: String(localized: "Authenticate to export the private key “\(identity.displayName)”.")
        )
    }
}
