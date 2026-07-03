import SwiftUI
import UniformTypeIdentifiers
import CypherdexCore

struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var showGenerate = false
    @State private var showImporter = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

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
                List {
                    Section {
                        ForEach(model.identities) { identity in
                            IdentityRow(identity: identity) { model.delete(identity) }
                        }
                    } footer: {
                        Text("Keys are stored in this Mac’s keychain and never leave the device. Secure Enclave private keys stay in the enclave.")
                            .font(.caption)
                    }
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
    }
}
