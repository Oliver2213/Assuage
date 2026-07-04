import SwiftUI
import CypherdexCore

struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var showGenerate = false
    @State private var showImport = false
    @State private var identityToDelete: AgeIdentity?
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Group {
            if model.identities.isEmpty {
                ContentUnavailableView {
                    Label("No Keys Yet", systemImage: "key")
                } description: {
                    Text("Generate an age keypair to start encrypting and decrypting. Secure Enclave keys never leave this Mac.")
                } actions: {
                    Button("Generate age Keypair…", systemImage: "plus") { showGenerate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach(model.identities) { identity in
                            IdentityRow(identity: identity) { requestDelete(identity) }
                        }
                    }
                    Divider()
                    Text("Keys are stored in your keychain. A keychain key stays on this Mac unless you turn on syncing when you create it, which shares it with your other devices via iCloud Keychain. Secure Enclave keys never sync — sealed by the enclave, they only work on the Mac that created them. You can export any key for backup, but an exported Secure Enclave key still only works on that Mac.")
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
                Button("Import Identity…", systemImage: "square.and.arrow.down") { showImport = true }
                Button("Generate…", systemImage: "plus") { showGenerate = true }
            }
        }
        .sheet(isPresented: $showGenerate) { GenerateKeySheet() }
        .sheet(isPresented: $showImport) { ImportKeysSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .generateKeypairRequested)) { _ in
            showGenerate = true
        }
        .confirmationDialog(
            "Delete “\(identityToDelete?.displayName ?? "")”?",
            isPresented: $isDeleteConfirmationPresented,
            presenting: identityToDelete
        ) { identity in
            Button("Delete Key", role: .destructive) { model.delete(identity) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can’t be undone. Export the key first if you might need it again.")
        }
    }

    private func requestDelete(_ identity: AgeIdentity) {
        identityToDelete = identity
        isDeleteConfirmationPresented = true
    }
}
