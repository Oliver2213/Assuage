import SwiftUI
import AssuageCore

/// Encrypt one kind of input, chosen by `scope`: a message/data field (Text panel)
/// or a queue of files and folders (Files panel). Recipient/passphrase controls are
/// shared; only the input, armor toggle, and output differ.
struct EncryptView: View {
    let scope: ComposeScope
    @Environment(AppModel.self) private var model
    @State private var viewModel = EncryptViewModel()
    @AppStorage(PreferenceKeys.confirmTouchIDBeforeEncrypt) private var confirmTouchIDBeforeEncrypt = false

    private var recipients: [AgeRecipient] {
        model.identities.filter { model.encryptRecipientIDs.contains($0.id) }.map(\.recipient)
            + model.encryptExtraRecipients
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner(banner)

                if scope == .text {
                    MultilineTextField(title: "Message", placeholder: "Message or data…", text: $model.encryptInput)
                }

                Picker("Encrypt to", selection: $model.encryptMode) {
                    Text("Recipients").tag(AppModel.CredentialMode.keys)
                    Text("Passphrase").tag(AppModel.CredentialMode.passphrase)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.encryptMode {
                case .keys:
                    GroupBox("Recipients") {
                        RecipientSelector(
                            identities: model.identities,
                            selectedIdentityIDs: $model.encryptRecipientIDs,
                            extraRecipients: $model.encryptExtraRecipients
                        )
                        .padding(4)
                    }
                case .passphrase:
                    GroupBox("Passphrase") {
                        VStack(alignment: .leading, spacing: 8) {
                            PassphraseField(prompt: "Passphrase", text: $model.encryptPassphrase)
                            PassphraseField(prompt: "Confirm passphrase", text: $model.encryptPassphraseConfirm)
                            if passphraseMismatch {
                                Label("Passphrases don’t match.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Stepper(value: $viewModel.workFactor, in: 12...22) {
                                Text("Work factor: \(viewModel.workFactor)")
                            }
                            Text("Higher resists guessing but is slower to encrypt and decrypt. 18 is age’s default.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }
                }

                if scope == .text {
                    Toggle("ASCII-armor the output (safe to paste as text)", isOn: $viewModel.armored)

                    HStack(spacing: 12) {
                        Button("Encrypt Message", systemImage: "lock", action: encryptMessage)
                            .buttonStyle(.borderedProminent)
                            .help("Encrypt (⌘Return)")
                            .disabled(model.encryptInput.isEmpty || !canEncrypt || viewModel.isRunning)
                        if viewModel.isRunning {
                            ProgressStrip(progress: viewModel.progress).frame(maxWidth: 280)
                        }
                        Spacer()
                    }

                    if let output = viewModel.output {
                        CipherOutputView(
                            title: "Encrypted",
                            output: output,
                            binarySaveName: "message.age",
                            allowsTextSave: true,
                            textSaveName: "message.age",
                            font: .caption.monospaced()
                        )
                    }
                }

                if scope == .files {
                    QueuedFilesSection(
                        caption: "Encrypts each file to a new **.age** next to the original. A folder is zipped to a single **.zip.age**.",
                        files: $model.queuedEncryptFiles,
                        runVerb: "Encrypt",
                        runIcon: "lock",
                        dropPrompt: "Drop files or folders to encrypt",
                        dropIcon: "arrow.down.doc",
                        isRunEnabled: canEncrypt && !viewModel.isRunning,
                        onRun: encryptFiles,
                        status: viewModel.fileStatus
                    )
                }
            }
            .padding(20)
        }
        .alert("Couldn’t encrypt", isPresented: $viewModel.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: model.runComposeAction) { _, run in
            // Only the visible Encrypt panel acts; both (Files + Text) are mounted.
            guard run, model.selection == scope.panel, model.operation == .encrypt else { return }
            model.runComposeAction = false
            runPrimaryAction()
        }
    }

    private var banner: LocalizedStringKey {
        scope == .text
            ? "**Encrypt text.** Type or paste a message or data, choose recipients (or a passphrase), and encrypt. Also available from the **Services** menu."
            : "**Encrypt files.** Drop files or folders to encrypt each to a new **.age** next to the original — a folder is zipped first. Also from Finder’s **Quick Actions**."
    }

    private func runPrimaryAction() {
        switch scope {
        case .text: encryptMessage()
        case .files: encryptFiles()
        }
    }

    /// Whether the current mode has what it needs to encrypt.
    private var canEncrypt: Bool {
        switch model.encryptMode {
        case .keys: return !recipients.isEmpty
        case .passphrase:
            return !model.encryptPassphrase.isEmpty && model.encryptPassphrase == model.encryptPassphraseConfirm
        }
    }

    private var passphraseMismatch: Bool {
        !model.encryptPassphrase.isEmpty
            && !model.encryptPassphraseConfirm.isEmpty
            && model.encryptPassphrase != model.encryptPassphraseConfirm
    }

    private func encryptMessage() {
        guard !model.encryptInput.isEmpty, canEncrypt, !viewModel.isRunning else { return }
        Task {
            guard await confirmEncryptIntent() else { return }
            switch model.encryptMode {
            case .keys:
                await viewModel.encryptMessage(model.encryptInput, to: recipients)
            case .passphrase:
                if await viewModel.encryptMessage(model.encryptInput, passphrase: model.encryptPassphrase) {
                    clearPassphrase()
                }
            }
        }
    }

    private func encryptFiles() {
        let files = model.queuedEncryptFiles
        guard !files.isEmpty, canEncrypt, !viewModel.isRunning else { return }
        Task {
            guard await confirmEncryptIntent() else { return }
            switch model.encryptMode {
            case .keys:
                await viewModel.encryptFiles(files, to: recipients)
            case .passphrase:
                if await viewModel.encryptFiles(files, passphrase: model.encryptPassphrase) {
                    clearPassphrase()
                }
            }
            model.queuedEncryptFiles.removeAll()
        }
    }

    private func clearPassphrase() {
        model.encryptPassphrase = ""
        model.encryptPassphraseConfirm = ""
    }

    /// When "Confirm with Touch ID before encrypting" is on, prompt first. An intent
    /// gate on an unlocked Mac, not a security boundary — encryption is public-key only.
    private func confirmEncryptIntent() async -> Bool {
        guard confirmTouchIDBeforeEncrypt else { return true }
        return await Authentication.authorize(reason: String(localized: "Confirm to encrypt."))
    }
}
