import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CypherdexCore

struct EncryptView: View {
    @Environment(AppModel.self) private var model
    @Environment(CryptoEngine.self) private var engine

    @State private var armored = true
    @State private var selectedIdentityIDs: Set<UUID> = []
    @State private var extraRecipients: [AgeRecipient] = []

    @State private var outputText: String?
    @State private var outputData: Data?
    @State private var fileStatus: String?

    @State private var errorMessage = ""
    @State private var isErrorPresented = false
    @State private var showFileImporter = false

    private var recipients: [AgeRecipient] {
        model.identities.filter { selectedIdentityIDs.contains($0.id) }.map(\.recipient) + extraRecipients
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Encrypt anything.** Type or paste a message, choose one or more recipients, and encrypt. Or select text/files anywhere and use **Services ▸ Encrypt with Cypherdex** (also in Finder’s right-click menu).")

                messageBox($model.encryptInput)
                GroupBox("Recipients") {
                    RecipientSelector(
                        identities: model.identities,
                        selectedIdentityIDs: $selectedIdentityIDs,
                        extraRecipients: $extraRecipients
                    )
                    .padding(4)
                }

                Toggle("ASCII-armor the output (safe to paste as text)", isOn: $armored)

                HStack(spacing: 12) {
                    Button("Encrypt Message", systemImage: "lock") { encryptMessage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.encryptInput.isEmpty || recipients.isEmpty || engine.isRunning)
                    if engine.isRunning {
                        ProgressStrip(progress: engine.progress).frame(maxWidth: 280)
                    }
                    Spacer()
                }

                if let outputText {
                    armoredOutput(outputText)
                } else if let outputData {
                    binaryOutput(outputData)
                }

                filesBox($model.queuedEncryptFiles)
            }
            .padding(20)
        }
        .navigationTitle("Encrypt")
        .alert("Couldn’t encrypt", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.queuedEncryptFiles.append(contentsOf: urls) }
        }
    }

    // MARK: Sections

    private func messageBox(_ text: Binding<String>) -> some View {
        GroupBox("Message") {
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("Secret message…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func filesBox(_ files: Binding<[URL]>) -> some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Encrypts each file to a new **.age** file next to the original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                QueuedFilesList(files: files)

                HStack {
                    Button("Add Files…", systemImage: "plus") { showFileImporter = true }
                    Button("Encrypt \(files.wrappedValue.count) File\(files.wrappedValue.count == 1 ? "" : "s")", systemImage: "lock") {
                        encryptQueuedFiles()
                    }
                    .disabled(files.wrappedValue.isEmpty || recipients.isEmpty || engine.isRunning)
                    Spacer()
                }

                FileWell(prompt: "Drop files to encrypt", systemImage: "arrow.down.doc") { urls in
                    files.wrappedValue.append(contentsOf: urls)
                }
                .frame(height: 76)

                if let fileStatus {
                    Label(fileStatus, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(4)
        }
    }

    private func armoredOutput(_ text: String) -> some View {
        GroupBox("Encrypted — armored text") {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                HStack {
                    Button("Copy", systemImage: "doc.on.doc") { copyToPasteboard(text) }
                    Button("Save…", systemImage: "square.and.arrow.down") {
                        SavePanel.save(text: text, suggestedName: "message.age")
                    }
                    Spacer()
                }
            }
            .padding(4)
        }
    }

    private func binaryOutput(_ data: Data) -> some View {
        GroupBox("Encrypted — \(ByteFormatting.size(Int64(data.count)))") {
            HStack {
                Text("Binary age file.").foregroundStyle(.secondary)
                Spacer()
                Button("Save…", systemImage: "square.and.arrow.down") {
                    SavePanel.save(data, suggestedName: "message.age")
                }
            }
            .padding(4)
        }
    }

    // MARK: Actions

    private func encryptMessage() {
        outputText = nil
        outputData = nil
        let recipients = self.recipients
        let armored = self.armored
        let text = model.encryptInput
        Task {
            do {
                let data = try await engine.encrypt(Data(text.utf8), to: recipients, armored: armored)
                if armored {
                    outputText = String(decoding: data, as: UTF8.self)
                } else {
                    outputData = data
                }
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

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
