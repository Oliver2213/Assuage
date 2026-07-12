import SwiftUI
import AssuageCore

struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var identityToDelete: AgeIdentity?
    @State private var isDeleteConfirmationPresented = false
    @AppStorage(PreferenceKeys.requireAuthToDelete) private var requireAuthToDelete = false

    var body: some View {
        Group {
            if model.identities.isEmpty {
                ContentUnavailableView {
                    Label("No Keys Yet", systemImage: "key")
                } description: {
                    Text("Generate an age keypair to start encrypting and decrypting. Secure Enclave keys never leave this Mac.")
                } actions: {
                    Button("Generate age Keypair…", systemImage: "plus") { model.showGenerateSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
                }
            } else {
                @Bindable var model = model
                VStack(spacing: 0) {
                    List(selection: $model.selectedKeyIDs) {
                        ForEach(model.identities) { identity in
                            IdentityRow(identity: identity) { requestDelete(identity) }
                                .tag(identity.id)
                        }
                    }
                    Divider()
                    Text("Keys live in your keychain. A local key stays on this Mac; a synced key shares to your other devices via iCloud Keychain; a Touch ID–protected key stays on this Mac and is sealed by the Secure Enclave, so its secret can’t be read at rest without authenticating. Secure Enclave keys never sync — they only work on the Mac that created them. You can export any key for backup, but an exported Secure Enclave key still only works on that Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .navigationTitle("Keys")
        .toolbar {
            ToolbarItemGroup {
                Button("Edit Key…", systemImage: "pencil") { model.editingKey = model.singleSelectedKey }
                    .disabled(model.singleSelectedKey == nil)
                Menu {
                    Button("Copy Recipients", systemImage: "doc.on.doc") { model.copyRecipients(for: model.selectedKeys) }
                    Button("Export Recipients…", systemImage: "square.and.arrow.up") { model.exportRecipients(for: model.selectedKeys) }
                } label: {
                    Label("Recipients", systemImage: "person.2")
                }
                .labelStyle(.titleAndIcon)
                .disabled(model.selectedKeys.isEmpty)
                Button("Export Identities…", systemImage: "key") { model.exportingKeys = ExportRequest(identities: model.selectedKeys) }
                    .disabled(model.selectedKeys.isEmpty)
                Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
                Button("Generate…", systemImage: "plus") { model.showGenerateSheet = true }
            }
        }
        .confirmationDialog(
            "Delete “\(identityToDelete?.displayName ?? "")”?",
            isPresented: $isDeleteConfirmationPresented,
            presenting: identityToDelete
        ) { identity in
            Button("Delete Key", role: .destructive) { performDelete(identity) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can’t be undone. Export the key first if you might need it again.")
        }
    }

    private func requestDelete(_ identity: AgeIdentity) {
        identityToDelete = identity
        isDeleteConfirmationPresented = true
    }

    /// Authenticate first when the preference asks for it, then delete.
    private func performDelete(_ identity: AgeIdentity) {
        Task {
            if requireAuthToDelete {
                let ok = await Authentication.authorize(
                    reason: String(localized: "Authenticate to delete the key “\(identity.displayName)”.")
                )
                guard ok else { return }
            }
            model.delete(identity)
        }
    }
}
