import SwiftUI
import AssuageCore

struct EncryptView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = EncryptViewModel()

    private var recipients: [AgeRecipient] {
        model.identities.filter { model.encryptRecipientIDs.contains($0.id) }.map(\.recipient)
            + model.encryptExtraRecipients
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Encrypt anything.** Type or paste a message, choose one or more recipients, and encrypt. Drop files or folders onto the well to encrypt them in place — a folder is zipped first. Also available from **Services** and Finder’s right-click menu.")

                MultilineTextField(title: "Message", placeholder: "Secret message…", text: $model.encryptInput)

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

                Toggle("ASCII-armor the output (safe to paste as text)", isOn: $viewModel.armored)

                HStack(spacing: 12) {
                    Button("Encrypt Message", systemImage: "lock", action: encryptMessage)
                        .buttonStyle(.borderedProminent)
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
            .padding(20)
        }
        .navigationTitle("Encrypt")
        .alert("Couldn’t encrypt", isPresented: $viewModel.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
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
        Task {
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
        Task {
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
}
