import SwiftUI
import CypherdexCore

struct EncryptView: View {
    @Environment(AppModel.self) private var model
    @Environment(CryptoEngine.self) private var engine

    @State private var armored = true
    @State private var output: CryptoOutput?
    @State private var fileStatus: String?
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    private var recipients: [AgeRecipient] {
        model.identities.filter { model.encryptRecipientIDs.contains($0.id) }.map(\.recipient)
            + model.encryptExtraRecipients
    }

    var body: some View {
        @Bindable var model = model
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

                Toggle("ASCII-armor the output (safe to paste as text)", isOn: $armored)

                HStack(spacing: 12) {
                    Button("Encrypt Message", systemImage: "lock", action: encryptMessage)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.encryptInput.isEmpty || recipients.isEmpty || engine.isRunning)
                    if engine.isRunning {
                        ProgressStrip(progress: engine.progress).frame(maxWidth: 280)
                    }
                    Spacer()
                }

                if let output {
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
                    isRunEnabled: !recipients.isEmpty && !engine.isRunning,
                    onRun: encryptQueuedFiles,
                    status: fileStatus
                )
            }
            .padding(20)
        }
        .navigationTitle("Encrypt")
        .alert("Couldn’t encrypt", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Actions

    private func encryptMessage() {
        output = nil
        let recipients = self.recipients
        let armored = self.armored
        let text = model.encryptInput
        Task {
            do {
                let data = try await engine.encrypt(Data(text.utf8), to: recipients, armored: armored)
                output = armored ? .text(String(decoding: data, as: UTF8.self)) : .binary(data)
            } catch {
                present(error)
            }
        }
    }

    private func encryptQueuedFiles() {
        let recipients = self.recipients
        let files = model.queuedEncryptFiles
        guard !recipients.isEmpty, !files.isEmpty else { return }
        Task {
            var succeeded = 0
            for url in files {
                do {
                    try await engine.encryptFile(at: url, to: url.appendingPathExtension("age"), recipients: recipients, armored: false)
                    succeeded += 1
                } catch {
                    present(error)
                }
            }
            fileStatus = "Encrypted \(succeeded) of \(files.count) file\(files.count == 1 ? "" : "s")."
            model.queuedEncryptFiles.removeAll()
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
