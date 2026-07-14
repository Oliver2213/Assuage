import SwiftUI
import AssuageCore

/// A detailed row for one note-signing key, with inline actions for copying and
/// exporting its verifier key, editing storage, and deleting it. Multi-select
/// actions live in the Keys list's context menu (see `KeysView`).
struct SigningKeyRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKeys.exportAuthPolicy) private var exportAuthPolicy: ExportAuthPolicy = .always
    let signer: SigningKey
    /// Ask the parent to confirm and perform deletion.
    let onRequestDelete: () -> Void

    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: signer.requiresPresence ? "signature" : "pencil.and.scribble")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(signer.displayName)
                    .font(.headline)
                Spacer()
                Text("Signing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            LabeledContent("Verifier key") {
                PublicKeyText(key: signer.verifierKeyEncoding)
            }
            LabeledContent("Key ID", value: signer.keyIDHex)
            LabeledContent("Created", value: signer.created.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Storage", value: signer.storageDescription)

            HStack(spacing: 8) {
                Button("Copy Verifier Key", systemImage: "doc.on.doc") { model.copyVerifierKey(for: signer) }
                Button("Export Verifier Key…", systemImage: "square.and.arrow.up") { model.exportVerifierKey(for: signer) }
                Button("Export Signing Key…", systemImage: "key") { exportSigningKey() }
                Spacer()
                Button("Edit", systemImage: "pencil") { model.editingSigner = signer }
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
        .alert("Couldn’t export signing key", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// Export the private signing key for backup. A protected key prompts for Touch
    /// ID during hydration; otherwise apply the soft export-auth gate first, matching
    /// how age identities export.
    private func exportSigningKey() {
        Task {
            do {
                if !signer.requiresPresence, exportAuthPolicy != .never {
                    let reason = String(localized: "Authenticate to export the signing key “\(signer.name)”.")
                    guard await Authentication.authorize(reason: reason) else { return }
                }
                try await model.exportSigningKey(signer)
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
            }
        }
    }
}
