import SwiftUI
import CypherdexCore

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
                InfoBanner("**Encrypt anything.** Type or paste a message, choose one or more recipients, and encrypt. Drop files onto the well to encrypt them in place. Also available from **Services** and Finder’s right-click menu.")

                MultilineTextField(title: "Message", placeholder: "Secret message…", text: $model.encryptInput)

                GroupBox("Recipients") {
                    RecipientSelector(
                        identities: model.identities,
                        selectedIdentityIDs: $model.encryptRecipientIDs,
                        extraRecipients: $model.encryptExtraRecipients
                    )
                    .padding(4)
                }

                Toggle("ASCII-armor the output (safe to paste as text)", isOn: $viewModel.armored)

                HStack(spacing: 12) {
                    Button("Encrypt Message", systemImage: "lock", action: encryptMessage)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.encryptInput.isEmpty || recipients.isEmpty || viewModel.isRunning)
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
                    caption: "Encrypts each file to a new **.age** file next to the original.",
                    files: $model.queuedEncryptFiles,
                    runVerb: "Encrypt",
                    runIcon: "lock",
                    dropPrompt: "Drop files to encrypt",
                    dropIcon: "arrow.down.doc",
                    isRunEnabled: !recipients.isEmpty && !viewModel.isRunning,
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

    private func encryptMessage() {
        Task { await viewModel.encryptMessage(model.encryptInput, to: recipients) }
    }

    private func encryptFiles() {
        let files = model.queuedEncryptFiles
        Task {
            await viewModel.encryptFiles(files, to: recipients)
            model.queuedEncryptFiles.removeAll()
        }
    }
}
