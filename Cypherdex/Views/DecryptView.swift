import SwiftUI
import CypherdexCore

struct DecryptView: View {
    @Environment(AppModel.self) private var model
    @Environment(CryptoEngine.self) private var engine

    @State private var output: CryptoOutput?
    @State private var statusMessage: String?
    @State private var statusIsGood = true
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    private var identities: [AgeIdentity] {
        model.identities.filter { model.decryptIdentityIDs.contains($0.id) }
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Decrypt with your identities.** Paste armored age text or queue files. **Check** tells you whether one of your keys can open something without decrypting it. Works from **Services** and Finder too.")

                MultilineTextField(
                    title: "Encrypted text",
                    placeholder: "-----BEGIN AGE ENCRYPTED FILE-----…",
                    text: $model.decryptInput,
                    font: .caption.monospaced()
                )

                GroupBox("Try these identities") {
                    if model.identities.isEmpty {
                        Text("No identities yet — generate or import one in the Keys tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    } else {
                        IdentityCheckGrid(identities: model.identities, selection: $model.decryptIdentityIDs, showsPresence: true)
                            .padding(4)
                    }
                }

                HStack(spacing: 12) {
                    Button("Decrypt", systemImage: "lock.open", action: decryptText)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.decryptInput.isEmpty || identities.isEmpty || engine.isRunning)
                    Button("Check", systemImage: "questionmark.circle", action: checkText)
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

                if let output {
                    CipherOutputView(title: "Decrypted", output: output, binarySaveName: "decrypted")
                }

                QueuedFilesSection(
                    caption: "Writes each decrypted file next to the encrypted one.",
                    files: $model.queuedDecryptFiles,
                    runVerb: "Decrypt",
                    runIcon: "lock.open",
                    dropPrompt: "Drop files to decrypt",
                    dropIcon: "arrow.up.doc",
                    isRunEnabled: !identities.isEmpty && !engine.isRunning,
                    onRun: decryptQueuedFiles
                )
            }
            .padding(20)
        }
        .navigationTitle("Decrypt")
        .onAppear {
            if model.decryptIdentityIDs.isEmpty { selectAll() }
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
    }

    // MARK: Actions

    private func decryptText() {
        output = nil
        statusMessage = nil
        let identities = self.identities
        let data = Data(model.decryptInput.utf8)
        Task {
            do {
                let plaintext = try await engine.decrypt(data, with: identities)
                if let text = String(data: plaintext, encoding: .utf8) {
                    output = .text(text)
                } else {
                    output = .binary(plaintext)
                }
            } catch {
                present(error)
            }
        }
    }

    private func checkText() {
        output = nil
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
        if model.decryptIdentityIDs.isEmpty { selectAll() }
        guard !model.decryptInput.isEmpty, !identities.isEmpty else { return }
        checkText()
    }

    private func decryptedDestination(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "age" {
            return url.deletingPathExtension()
        }
        return url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".decrypted")
    }

    private func selectAll() {
        model.decryptIdentityIDs = Set(model.identities.map(\.id))
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
