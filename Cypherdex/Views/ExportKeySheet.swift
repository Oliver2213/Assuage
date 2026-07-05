import SwiftUI
import CypherdexCore

/// Export one or more identities (private keys) as a single text file, protected
/// by recipients, a passphrase, or — deliberately — not at all. Reveals the
/// secrets only after the export-auth check (and Touch ID for protected keys).
struct ExportKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKeys.exportAuthPolicy) private var exportAuthPolicy: ExportAuthPolicy = .always
    @AppStorage(PreferenceKeys.allowClipboardExport) private var allowClipboardExport = false

    let identities: [AgeIdentity]

    private enum Mode: Hashable { case recipients, passphrase, plaintext }
    private enum Destination { case file, clipboard }

    @State private var mode: Mode = .recipients
    @State private var selectedRecipientIDs: Set<UUID> = []
    @State private var extraRecipients: [AgeRecipient] = []
    @State private var passphrase = ""
    @State private var passphraseConfirm = ""
    @State private var workFactor = Cipher.defaultWorkFactor
    @State private var engine = CryptoEngine()
    @State private var isExporting = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    private var recipients: [AgeRecipient] {
        model.identities.filter { selectedRecipientIDs.contains($0.id) }.map(\.recipient) + extraRecipients
    }
    private var passphraseMismatch: Bool {
        !passphrase.isEmpty && !passphraseConfirm.isEmpty && passphrase != passphraseConfirm
    }
    private var canExport: Bool {
        switch mode {
        case .recipients: return !recipients.isEmpty
        case .passphrase: return !passphrase.isEmpty && passphrase == passphraseConfirm
        case .plaintext: return true
        }
    }
    private var isBundle: Bool { identities.count > 1 }
    private var title: LocalizedStringKey { isBundle ? "Export Identities" : "Export Identity" }
    private var fileBase: String {
        isBundle ? "\(AppInfo.name)-Identities" : (identities.first?.displayName.replacingOccurrences(of: " ", with: "-") ?? "identity")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            Form {
                if isBundle {
                    LabeledContent("Keys") {
                        Text("^[\(identities.count) identity](inflect: true)")
                    }
                } else {
                    LabeledContent("Key", value: identities.first?.displayName ?? "")
                }
                Picker("Protection", selection: $mode) {
                    Text("Recipients").tag(Mode.recipients)
                    Text("Passphrase").tag(Mode.passphrase)
                    Text("Plaintext").tag(Mode.plaintext)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            switch mode {
            case .recipients:
                GroupBox("Recipients") {
                    RecipientSelector(
                        identities: model.identities,
                        selectedIdentityIDs: $selectedRecipientIDs,
                        extraRecipients: $extraRecipients
                    )
                    .padding(4)
                }
                Text("The exported file is encrypted to these recipients — only they can open it, and any of them can re-import the keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .passphrase:
                GroupBox("Passphrase") {
                    VStack(alignment: .leading, spacing: 8) {
                        PassphraseField(prompt: "Passphrase", text: $passphrase)
                        PassphraseField(prompt: "Confirm passphrase", text: $passphraseConfirm)
                        if passphraseMismatch {
                            Label("Passphrases don’t match.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Stepper(value: $workFactor, in: 12...22) {
                            Text("Work factor: \(workFactor)")
                        }
                    }
                    .padding(4)
                }
            case .plaintext:
                Label("The file will hold your private \(isBundle ? "keys" : "key") with no protection. Anyone who gets it can read messages sent to you and impersonate you. Store it somewhere safe.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isExporting)
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                }
                if allowClipboardExport {
                    Button("Copy to Clipboard") { export(to: .clipboard) }
                        .disabled(!canExport || isExporting)
                }
                Button("Save…") { export(to: .file) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canExport || isExporting)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Couldn’t export", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func export(to destination: Destination) {
        isExporting = true
        Task {
            do {
                // Every protected key hardware-prompts during hydration; apply the
                // soft export-auth gate only when at least one key wouldn't.
                let allHardware = identities.allSatisfy { $0.keychainProtection?.requiresAuthentication == true }
                if !allHardware, needsSoftAuth {
                    guard await Authentication.authorize(reason: authReason) else { isExporting = false; return }
                }
                let hydrated = try await model.hydratedSecrets(for: identities)
                let combined = hydrated.map { $0.ageFormatted(generator: AppInfo.name) }.joined(separator: "\n")
                let (text, name) = try await render(combined)
                switch destination {
                case .file: SavePanel.save(text: text, suggestedName: name)
                case .clipboard: Pasteboard.copy(text, sensitive: true)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
                isExporting = false
            }
        }
    }

    /// Turn the combined age text into the bytes to write, per the chosen mode.
    private func render(_ ageText: String) async throws -> (text: String, name: String) {
        switch mode {
        case .plaintext:
            return (ageText, "\(fileBase).txt")
        case .recipients:
            let data = try await engine.encrypt(Data(ageText.utf8), to: recipients, armored: true)
            return (String(decoding: data, as: UTF8.self), "\(fileBase).age")
        case .passphrase:
            let data = try await engine.encrypt(Data(ageText.utf8), passphrase: passphrase, armored: true, workFactor: workFactor)
            return (String(decoding: data, as: UTF8.self), "\(fileBase).age")
        }
    }

    private var needsSoftAuth: Bool {
        switch exportAuthPolicy {
        case .always: return true
        case .keychainOnly: return identities.contains { $0.source != .secureEnclave }
        case .never: return false
        }
    }

    private var authReason: String {
        if let only = identities.first, identities.count == 1 {
            return String(localized: "Authenticate to export the private key “\(only.displayName)”.")
        }
        return String(localized: "Authenticate to export \(identities.count) private keys.")
    }
}
