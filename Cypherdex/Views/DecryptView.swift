import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CypherdexCore

struct DecryptView: View {
    @Environment(AppModel.self) private var model
    @Environment(CryptoEngine.self) private var engine

    @State private var ciphertext = ""
    @State private var selectedIdentityIDs: Set<UUID> = []

    @State private var outputText: String?
    @State private var outputData: Data?
    @State private var statusMessage: String?
    @State private var statusIsGood = true

    @State private var errorMessage = ""
    @State private var isErrorPresented = false
    @State private var showFileImporter = false

    private var identities: [AgeIdentity] {
        model.identities.filter { selectedIdentityIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Decrypt with your identities.** Paste armored age text or drop an encrypted file. **Check** tells you whether one of your keys can open a file without decrypting it.")

                GroupBox("Encrypted text") {
                    TextEditor(text: $ciphertext)
                        .font(.caption.monospaced())
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if ciphertext.isEmpty {
                                Text("-----BEGIN AGE ENCRYPTED FILE-----…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                identitiesBox

                HStack(spacing: 12) {
                    Button("Decrypt", systemImage: "lock.open") { decryptText() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ciphertext.isEmpty || identities.isEmpty || engine.isRunning)
                    Button("Check", systemImage: "questionmark.circle") { checkText() }
                        .disabled(ciphertext.isEmpty || identities.isEmpty || engine.isRunning)
                    if engine.isRunning {
                        ProgressStrip(progress: engine.progress).frame(maxWidth: 260)
                    }
                    Spacer()
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: statusIsGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(statusIsGood ? .green : .orange)
                }

                if let outputText {
                    textOutput(outputText)
                } else if let outputData {
                    binaryOutput(outputData)
                }

                filesBox
            }
            .padding(20)
        }
        .navigationTitle("Decrypt")
        .onAppear { if selectedIdentityIDs.isEmpty { selectAll() } }
        .alert("Couldn’t decrypt", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { decryptFile(url) }
        }
    }

    // MARK: Sections

    private var identitiesBox: some View {
        GroupBox("Try these identities") {
            VStack(alignment: .leading, spacing: 8) {
                if model.identities.isEmpty {
                    Text("No identities yet — generate or import one in the Keys tab.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.identities) { identity in
                        Toggle(isOn: isSelected(identity)) {
                            HStack(spacing: 6) {
                                IdentityLabel(identity: identity)
                                if identity.requiresPresence {
                                    Image(systemName: "touchid")
                                        .foregroundStyle(.secondary)
                                        .help("Using this key prompts for Touch ID or your passcode.")
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(4)
        }
    }

    private var filesBox: some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Writes the decrypted file next to the encrypted one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Decrypt File…", systemImage: "doc.badge.gearshape") { showFileImporter = true }
                        .disabled(identities.isEmpty || engine.isRunning)
                    Spacer()
                }
                FileWell(prompt: "Drop files to decrypt", systemImage: "arrow.up.doc") { urls in
                    urls.forEach(decryptFile)
                }
                .frame(height: 84)
            }
            .padding(4)
        }
    }

    private func textOutput(_ text: String) -> some View {
        GroupBox("Decrypted text") {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(text)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                HStack {
                    Button("Copy", systemImage: "doc.on.doc") { copyToPasteboard(text) }
                    Spacer()
                }
            }
            .padding(4)
        }
    }

    private func binaryOutput(_ data: Data) -> some View {
        GroupBox("Decrypted — \(ByteFormatting.size(Int64(data.count)))") {
            HStack {
                Text("The plaintext isn’t valid text.").foregroundStyle(.secondary)
                Spacer()
                Button("Save…", systemImage: "square.and.arrow.down") {
                    SavePanel.save(data, suggestedName: "decrypted")
                }
            }
            .padding(4)
        }
    }

    // MARK: Actions

    private func decryptText() {
        outputText = nil
        outputData = nil
        statusMessage = nil
        let identities = self.identities
        let data = Data(ciphertext.utf8)
        Task {
            do {
                let plaintext = try await engine.decrypt(data, with: identities)
                if let text = String(data: plaintext, encoding: .utf8) {
                    outputText = text
                } else {
                    outputData = plaintext
                }
            } catch {
                present(error)
            }
        }
    }

    private func checkText() {
        outputText = nil
        outputData = nil
        let can = Cipher.canDecrypt(Data(ciphertext.utf8), with: identities)
        statusIsGood = can
        statusMessage = can
            ? "One of your selected identities can decrypt this."
            : "None of your selected identities can decrypt this."
    }

    private func decryptFile(_ url: URL) {
        guard !identities.isEmpty else { return }
        let destination = decryptedDestination(for: url)
        let identities = self.identities
        Task {
            do {
                try await engine.decryptFile(at: url, to: destination, identities: identities)
                statusIsGood = true
                statusMessage = "Decrypted \(url.lastPathComponent) → \(destination.lastPathComponent)"
            } catch {
                present(error)
            }
        }
    }

    private func decryptedDestination(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "age" {
            return url.deletingPathExtension()
        }
        return url.deletingPathExtension()
            .appendingPathExtension(url.pathExtension + ".decrypted")
    }

    // MARK: Helpers

    private func isSelected(_ identity: AgeIdentity) -> Binding<Bool> {
        Binding(
            get: { selectedIdentityIDs.contains(identity.id) },
            set: { isOn in
                if isOn { selectedIdentityIDs.insert(identity.id) }
                else { selectedIdentityIDs.remove(identity.id) }
            }
        )
    }

    private func selectAll() {
        selectedIdentityIDs = Set(model.identities.map(\.id))
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
