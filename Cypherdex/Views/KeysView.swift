import SwiftUI
import UniformTypeIdentifiers
import CypherdexCore

struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var showGenerate = false
    @State private var showImporter = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false
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
                    Text("Keys are stored in this Mac’s keychain and never sync off the device. You can export any key for backup — including Secure Enclave keys — but a Secure Enclave key is sealed by the enclave, so it only works on the Mac that created it.")
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
                Button("Import Identity…", systemImage: "square.and.arrow.down") { showImporter = true }
                Button("Generate…", systemImage: "plus") { showGenerate = true }
            }
        }
        .sheet(isPresented: $showGenerate) { GenerateKeySheet() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                try model.importIdentityFile(at: url)
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .generateKeypairRequested)) { _ in
            showGenerate = true
        }
        .alert("Couldn’t import identity", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
