import SwiftUI
import AssuageCore

/// Sign text as a C2SP signed note. Paste an already-signed note and its signatures
/// are pulled aside into a list, kept alongside your new one unless you edit the
/// text (which would invalidate them).
struct SignView: View {
    @Environment(AppModel.self) private var model
    @State private var isSigning = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner("**Sign a note.** Type or paste text, choose a signing key, and sign. Paste a note that’s already signed to add your signature alongside the others.")

                MultilineTextField(title: "Note", placeholder: "Text to sign…", text: $model.signInput)
                    .onChange(of: model.signInput) { _, newValue in pullOutSignatures(from: newValue) }

                if !model.signKeptSignatures.isEmpty {
                    SignatureList(
                        note: SignedNote(text: model.signPastedText ?? model.signInput, signatures: model.signKeptSignatures),
                        verifierKeys: model.verifierKeys,
                        title: "Existing signatures"
                    )
                    Toggle("Keep other signatures when signing", isOn: $model.keepOtherSignatures)
                        .disabled(!model.signTextUnchanged)
                    if !model.signTextUnchanged {
                        Text("You changed the text, so the existing signatures no longer match it and won’t be kept.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                signerControl

                if model.signIdentityID != nil {
                    HStack(spacing: 12) {
                        Button("Sign Note", systemImage: "signature", action: sign)
                            .buttonStyle(.borderedProminent)
                            .help("Sign (⌘Return)")
                            .disabled(!canSign || isSigning)
                        if isSigning { ProgressView().controlSize(.small) }
                        Spacer()
                    }
                }

                if let output = model.signOutput {
                    CipherOutputView(
                        title: "Signed note",
                        output: .text(output),
                        binarySaveName: "note.txt",
                        allowsTextSave: true,
                        textSaveName: "note.txt",
                        font: .callout.monospaced()
                    )
                }
            }
            .padding(20)
        }
        .alert("Couldn’t sign", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if model.signIdentityID == nil { model.signIdentityID = model.signingKeys.first?.id }
        }
        .onChange(of: model.runComposeAction) { _, run in
            guard run, model.selection == .notes, model.noteOperation == .sign else { return }
            model.runComposeAction = false
            sign()
        }
    }

    /// The signing-key picker, or a prompt to make one when there are none.
    @ViewBuilder private var signerControl: some View {
        @Bindable var model = model
        if model.signingKeys.isEmpty {
            GroupBox("Signing key") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You don’t have a signing key yet.")
                        .foregroundStyle(.secondary)
                    Button("Generate Signing Key…", systemImage: "plus") { model.showGenerateSigningKeySheet = true }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        } else {
            Picker("Sign with", selection: $model.signIdentityID) {
                ForEach(model.signingKeys) { signer in
                    Text(signer.name).tag(Optional(signer.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var canSign: Bool {
        !model.signInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.signIdentityID != nil
    }

    /// When a full signed note is pasted, split its signatures out of the text field
    /// into the kept-signatures list, leaving just the text to edit.
    private func pullOutSignatures(from text: String) {
        let parsed = SignedNote(parsing: text)
        guard !parsed.signatures.isEmpty else { return }
        model.signKeptSignatures = parsed.signatures
        model.signPastedText = parsed.text
        model.keepOtherSignatures = true
        // Leaves just the text; re-parsing it finds no block, so this won't re-fire.
        model.signInput = parsed.text
    }

    private func sign() {
        guard canSign, !isSigning else { return }
        isSigning = true
        Task {
            do {
                model.signOutput = try await model.signNote()
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
            }
            isSigning = false
        }
    }
}
