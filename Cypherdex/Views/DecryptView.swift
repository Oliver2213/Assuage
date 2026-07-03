import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CypherdexCore

struct DecryptView: View {
    @Environment(AppModel.self) private var model
    @Environment(CryptoEngine.self) private var engine

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
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Decrypt with your identities.** Paste armored age text or queue files. **Check** tells you whether one of your keys can open something without decrypting it. Works from **Services** and Finder too.")

                cipherBox($model.decryptInput)
                identitiesBox

                HStack(spacing: 12) {
                    Button("Decrypt", systemImage: "lock.open") { decryptText() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.decryptInput.isEmpty || identities.isEmpty || engine.isRunning)
                    Button("Check", systemImage: "questionmark.circle") { checkText() }
                        .disabled(model.decryptInput.isEmpty || identities.isEmpty || engine.isRunning)
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

                filesBox($model.queuedDecryptFiles)
            }
            .padding(20)
        }
        .navigationTitle("Decrypt")
        .onAppear {
            if selectedIdentityIDs.isEmpty { selectAll() }
            runAutoCheckIfNeeded()
        }
        .onChange(of: model.autoCheckRequested) { _, requested in
            if requested { runAutoCheckIfNeeded() }
        }
        .alert("Couldn’t decrypt", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.queuedDecryptFiles.append(contentsOf: urls) }
        }
    }

    // MARK: Sections

    private func cipherBox(_ text: Binding<String>) -> some View {
        GroupBox("Encrypted text") {
            TextEditor(text: text)
                .font(.caption.monospaced())
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("-----BEGIN AGE ENCRYPTED FILE-----…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

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

    private func filesBox(_ files: Binding<[URL]>) -> some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Writes each decrypted file next to the encrypted one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                QueuedFilesList(files: files)

                HStack {
                    Button("Add Files…", systemImage: "plus") { showFileImporter = true }
                    Button("Decrypt \(files.wrappedValue.count) File\(files.wrappedValue.count == 1 ? "" : "s")", systemImage: "lock.open") {
                        decryptQueuedFiles()
                    }
                    .disabled(files.wrappedValue.isEmpty || identities.isEmpty || engine.isRunning)
                    Spacer()
                }

                FileWell(prompt: "Drop files to decrypt", systemImage: "arrow.up.doc") { urls in
                    files.wrappedValue.append(contentsOf: urls)
                }
                .frame(height: 76)
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
        let data = Data(model.decryptInput.utf8)
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
        let can = Cipher.canDecrypt(Data(model.decryptInput.utf8), with: identities)
        statusIsGood = can
        statusMessage = can
            ? "One of your selected identities can decrypt this."
            : "None of your selected identities can decrypt this."
    }

    private func decryptQueuedFiles() {
        let identities = self.identities
        let files = model.queuedDecryptFiles
        guard !identities.isEmpty, !files.isEmpty else { return }
        Task {
            var succeeded = 0
            for url in files {
                do {
                    try await engine.decryptFile(at: url, to: decryptedDestination(for: url), identities: identities)
                    succeeded += 1
                } catch {
                    present(error)
                }
            }
            statusIsGood = succeeded == files.count
            statusMessage = "Decrypted \(succeeded) of \(files.count) file\(files.count == 1 ? "" : "s")."
            model.queuedDecryptFiles.removeAll()
        }
    }

    private func runAutoCheckIfNeeded() {
        guard model.autoCheckRequested else { return }
        model.autoCheckRequested = false
        if selectedIdentityIDs.isEmpty { selectAll() }
        guard !model.decryptInput.isEmpty, !identities.isEmpty else { return }
        checkText()
    }

    private func decryptedDestination(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "age" {
            return url.deletingPathExtension()
        }
        return url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".decrypted")
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
