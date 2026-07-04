import SwiftUI
import CypherdexCore

struct DecryptView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = DecryptViewModel()
    /// Header info for the queued files, refreshed when the queue changes.
    @State private var fileInfos: [URL: AgeFileInfo] = [:]

    private var identities: [AgeIdentity] {
        model.identities.filter { model.decryptIdentityIDs.contains($0.id) }
    }

    /// Header info for the pasted text, when it parses as an age file.
    private var inputInfo: AgeFileInfo? {
        guard !model.decryptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? AgeFileInspector.inspect(Data(model.decryptInput.utf8))
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Decrypt with your identities.** Paste armored age text or queue files. **Check** tells you whether one of your keys can open something without decrypting it. Works from **Services** and Finder too.")

                MultilineTextField(
                    title: "Encrypted text",
                    placeholder: "-----BEGIN AGE ENCRYPTED FILE-----…",
                    text: $model.decryptInput,
                    font: .caption.monospaced()
                )

                if let inputInfo {
                    AgeFileInfoView(info: inputInfo, decryptability: decryptability(of: inputInfo))
                }

                Picker("Decrypt with", selection: $model.decryptMode) {
                    Text("Identities").tag(AppModel.CredentialMode.keys)
                    Text("Passphrase").tag(AppModel.CredentialMode.passphrase)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.decryptMode {
                case .keys:
                    GroupBox("Try these identities") {
                        if model.identities.isEmpty {
                            Text("No identities yet — generate or import one in the Keys tab.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        } else {
                            IdentityCheckTable(identities: model.identities, selection: $model.decryptIdentityIDs, showsPresence: true)
                                .padding(4)
                        }
                    }
                case .passphrase:
                    GroupBox("Passphrase") {
                        PassphraseField(prompt: "Passphrase", text: $model.decryptPassphrase)
                            .padding(4)
                    }
                }

                HStack(spacing: 12) {
                    Button("Decrypt", systemImage: "lock.open", action: decrypt)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.decryptInput.isEmpty || !canDecrypt || viewModel.isRunning)
                    if model.decryptMode == .keys {
                        Button("Check", systemImage: "questionmark.circle", action: check)
                            .disabled(model.decryptInput.isEmpty || identities.isEmpty || viewModel.isRunning)
                    }
                    if viewModel.isRunning {
                        ProgressStrip(progress: viewModel.progress).frame(maxWidth: 260)
                    }
                    Spacer()
                }

                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: viewModel.statusIsGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(viewModel.statusIsGood ? .green : .orange)
                }

                if let output = viewModel.output {
                    CipherOutputView(title: "Decrypted", output: output, binarySaveName: "decrypted", sensitive: true)
                }

                QueuedFilesSection(
                    caption: "Writes each decrypted file next to the encrypted one.",
                    files: $model.queuedDecryptFiles,
                    runVerb: "Decrypt",
                    runIcon: "lock.open",
                    dropPrompt: "Drop files to decrypt",
                    dropIcon: "arrow.up.doc",
                    isRunEnabled: canDecrypt && !viewModel.isRunning,
                    onRun: decryptFiles
                )

                ForEach(model.queuedDecryptFiles, id: \.self) { url in
                    if let info = fileInfos[url] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            AgeFileInfoView(info: info, decryptability: decryptability(of: info))
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Decrypt")
        .onAppear {
            if model.decryptIdentityIDs.isEmpty { selectAllIdentities() }
            runAutoCheckIfNeeded()
            refreshFileInfos()
        }
        .onChange(of: model.queuedDecryptFiles) { refreshFileInfos() }
        .onChange(of: model.autoCheckRequested) { _, requested in
            if requested { runAutoCheckIfNeeded() }
        }
        .alert("Couldn’t decrypt", isPresented: $viewModel.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    /// The header-only "can you open this?" verdict for an inspected file, or nil
    /// when there are no identities to judge against (keeps the row hidden on a
    /// fresh install). Uses only public key material — nothing is unlocked.
    private func decryptability(of info: AgeFileInfo) -> DecryptionCapability? {
        model.identities.isEmpty ? nil : info.decryptability(with: model.identities)
    }

    /// Whether the current mode has what it needs to decrypt.
    private var canDecrypt: Bool {
        switch model.decryptMode {
        case .keys: return !identities.isEmpty
        case .passphrase: return !model.decryptPassphrase.isEmpty
        }
    }

    private func decrypt() {
        Task {
            switch model.decryptMode {
            case .keys:
                guard let identities = await hydratedIdentities() else { return }
                await viewModel.decrypt(model.decryptInput, with: identities)
            case .passphrase:
                if await viewModel.decrypt(model.decryptInput, passphrase: model.decryptPassphrase) {
                    model.decryptPassphrase = ""
                }
            }
        }
    }

    private func check() {
        Task {
            guard let identities = await hydratedIdentities() else { return }
            await viewModel.check(model.decryptInput, with: identities)
        }
    }

    private func decryptFiles() {
        let files = model.queuedDecryptFiles
        Task {
            switch model.decryptMode {
            case .keys:
                guard let identities = await hydratedIdentities() else { return }
                await viewModel.decryptFiles(files, with: identities)
            case .passphrase:
                if await viewModel.decryptFiles(files, passphrase: model.decryptPassphrase) {
                    model.decryptPassphrase = ""
                }
            }
            model.queuedDecryptFiles.removeAll()
        }
    }

    /// Unlock the selected identities' secrets (one Touch ID prompt covers any
    /// protected keys). Returns nil if the user cancels, so the caller aborts.
    private func hydratedIdentities() async -> [AgeIdentity]? {
        try? await model.hydratedSecrets(for: identities)
    }

    private func runAutoCheckIfNeeded() {
        guard model.autoCheckRequested, model.decryptMode == .keys else { return }
        model.autoCheckRequested = false
        if model.decryptIdentityIDs.isEmpty { selectAllIdentities() }
        guard !model.decryptInput.isEmpty, !identities.isEmpty else { return }
        check()
    }

    private func selectAllIdentities() {
        model.decryptIdentityIDs = Set(model.identities.map(\.id))
    }

    /// Inspect each queued file's header (a cheap, mapped read) so its recipient
    /// types and size breakdown can be shown alongside the queue.
    private func refreshFileInfos() {
        var infos: [URL: AgeFileInfo] = [:]
        for url in model.queuedDecryptFiles {
            if let info = try? AgeFileInspector.inspect(contentsOf: url) { infos[url] = info }
        }
        fileInfos = infos
    }
}
