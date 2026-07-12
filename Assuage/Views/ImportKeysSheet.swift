import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AssuageCore

/// Import age identities with per-key control, from a file or the clipboard.
/// First you set defaults (name, storage, whether to delete the file afterward),
/// then choose a source; every `AGE-SECRET-KEY-1…` it contains becomes an
/// editable row you can rename, restorage, or deselect before finalizing.
struct ImportKeysSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Where the keys under review came from.
    private enum ImportSource {
        case file(URL)
        case clipboard
    }

    // Defaults, chosen before picking a source.
    @State private var defaultName = ""
    @State private var defaultStorage: KeyStorage = .touchID
    @State private var defaultAuth: KeychainAuth = .biometryOrPasscode
    @State private var deleteFileAfter = false

    // Populated once keys are parsed from a file or the clipboard.
    @State private var source: ImportSource?
    @State private var drafts: [ImportKeyDraft] = []

    @State private var showLossConfirmation = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    // An encrypted OpenSSH key found in a source, awaiting its passphrase.
    @State private var pendingSSHText: String?
    @State private var pendingSSHSource: ImportSource?
    @State private var sshPassphrase = ""
    @State private var isPassphrasePresented = false

    // A passphrase-encrypted identity file, awaiting its passphrase.
    @State private var pendingEncryptedData: Data?
    @State private var pendingEncryptedSource: ImportSource?
    @State private var filePassphrase = ""
    @State private var isFilePassphrasePresented = false
    /// How many duplicate keys within the source were collapsed on load.
    @State private var duplicatesRemoved = 0

    private var hasSource: Bool { source != nil }
    private var isClipboardSource: Bool { if case .clipboard = source { return true }; return false }
    private var selectedCount: Int { drafts.filter(\.include).count }
    private var droppedCount: Int { drafts.count - selectedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Keys")
                .font(.title2.bold())

            Form {
                TextField("Default name", text: $defaultName, prompt: Text("Optional — overrides names below"))
                Picker("Storage", selection: $defaultStorage) {
                    ForEach(KeyStorage.keychainCases) { Text($0.title).tag($0) }
                }
                if defaultStorage == .touchID {
                    Picker("Require", selection: $defaultAuth) {
                        ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                if !isClipboardSource {
                    Toggle("Delete the file after importing", isOn: $deleteFileAfter)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: defaultName) { applyDefaultNames() }
            .onChange(of: defaultStorage) { applyDefaultStorage() }

            if defaultStorage == .touchID, defaultAuth == .currentBiometry {
                Label("“Current fingerprints” ties these keys to your fingerprints as they are now — adding or removing any fingerprint permanently makes them unreadable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasSource {
                ImportReviewList(drafts: $drafts, duplicatesRemoved: duplicatesRemoved)
            } else {
                Text("Choose an identity file or paste from the clipboard: age keys (`AGE-SECRET-KEY-1…`) or an SSH Ed25519 private key (`~/.ssh/id_ed25519`, passphrase-protected is fine). You’ll review and name each key before it’s imported. Imported keys are stored in your keychain — the Secure Enclave can only hold keys it generated itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if hasSource {
                    Button("Clear", role: .destructive, action: reset)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                if hasSource {
                    Button("Import", action: startImport)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                        .disabled(selectedCount == 0)
                } else {
                    Button("Paste from Clipboard", action: pasteFromClipboard)
                    Button("Choose File…", action: chooseFile)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Passphrase-protected SSH key", isPresented: $isPassphrasePresented) {
            SecureField("Passphrase", text: $sshPassphrase)
            Button("Import", action: importWithPassphrase)
            Button("Cancel", role: .cancel) { sshPassphrase = "" }
        } message: {
            Text("This SSH key is encrypted. Enter its passphrase to import it. Only the key is stored afterward — the passphrase isn’t kept.")
        }
        .confirmationDialog(
            "Delete the file with unselected keys?",
            isPresented: $showLossConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import & Delete File", role: .destructive, action: finishImport)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("^[\(droppedCount) key](inflect: true) not selected for import will be lost when the file is deleted.")
        }
        .alert("Couldn’t import keys", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Passphrase-protected identity file", isPresented: $isFilePassphrasePresented) {
            SecureField("Passphrase", text: $filePassphrase)
            Button("Import", action: decryptFileAndHandle)
            Button("Cancel", role: .cancel) { filePassphrase = "" }
        } message: {
            Text("This identity file is encrypted with a passphrase. Enter it to read the keys inside.")
        }
        .onAppear {
            // Opened from Finder: load the handed-in identity file once.
            if let url = model.pendingImportURL {
                model.pendingImportURL = nil
                load(url)
            }
        }
    }

    // MARK: Loading & editing

    /// Present an open panel starting in `~/.ssh` (where SSH keys live), falling
    /// back to home; hidden files are shown so `.ssh` and dotfiles are reachable.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ssh = home.appendingPathComponent(".ssh", isDirectory: true)
        panel.directoryURL = FileManager.default.fileExists(atPath: ssh.path) ? ssh : home
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    private func load(_ url: URL) {
        // A passphrase-encrypted identity file is itself an age file — prompt for
        // its passphrase and decrypt before parsing. Otherwise it's plaintext keys.
        if AgeFileInspector.isAgeFile(at: url) {
            do {
                pendingEncryptedData = try Data(contentsOf: url)
                pendingEncryptedSource = .file(url)
                filePassphrase = ""
                isFilePassphrasePresented = true
            } catch {
                present(error.localizedDescription)
            }
        } else {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                handle(text: text, source: .file(url))
            } catch {
                present(error.localizedDescription)
            }
        }
    }

    /// Decrypt a passphrase-protected identity file, then parse the keys inside it
    /// with the normal path. A wrong passphrase surfaces as an import error.
    private func decryptFileAndHandle() {
        guard let data = pendingEncryptedData, let source = pendingEncryptedSource else { return }
        defer { filePassphrase = ""; pendingEncryptedData = nil; pendingEncryptedSource = nil }
        do {
            let plaintext = try Cipher.decrypt(data, passphrase: filePassphrase)
            handle(text: String(decoding: plaintext, as: UTF8.self), source: source)
        } catch {
            present(error.localizedDescription)
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            present(String(localized: "The clipboard doesn’t contain any text."))
            return
        }
        handle(text: text, source: .clipboard)
    }

    /// Scan text from either source. Unencrypted age/SSH keys become review rows
    /// directly; an encrypted SSH key (found but unparseable) triggers a
    /// passphrase prompt; anything else is an error.
    private func handle(text: String, source: ImportSource) {
        let keys = AgeIdentity.importableKeys(from: text)
        if keys.isEmpty, AgeIdentity.containsOpenSSHPrivateKey(text) {
            pendingSSHText = text
            pendingSSHSource = source
            sshPassphrase = ""
            isPassphrasePresented = true
            return
        }
        guard !keys.isEmpty else {
            present(String(localized: "No keys to import — expected an age key (AGE-SECRET-KEY-1…) or an SSH Ed25519 private key."))
            return
        }
        buildDrafts(from: keys, source: source)
    }

    private func importWithPassphrase() {
        guard let text = pendingSSHText, let source = pendingSSHSource else { return }
        defer { sshPassphrase = ""; pendingSSHText = nil; pendingSSHSource = nil }
        do {
            let keys = try AgeIdentity.importableSSHKeys(from: text, passphrase: sshPassphrase)
            buildDrafts(from: keys, source: source)
        } catch {
            present(error.localizedDescription)
        }
    }

    /// Turn parsed keys into editable rows: collapse duplicates within the source
    /// (same recipient), and pre-deselect any we already hold. Shared by the file
    /// and clipboard paths.
    private func buildDrafts(from keys: [ImportableKey], source: ImportSource) {
        var seen = Set<AgeRecipient>()
        let unique = keys.filter { seen.insert($0.recipient).inserted }
        let existing = Set(model.identities.map(\.recipient))
        self.source = source
        duplicatesRemoved = keys.count - unique.count
        drafts = unique.map { key in
            let alreadyExists = existing.contains(key.recipient)
            // Keys we already hold default to skipped, but stay togglable in case
            // the user deliberately wants a second, separately-labeled copy.
            return ImportKeyDraft(key: key, include: !alreadyExists, name: "", storage: defaultStorage, alreadyExists: alreadyExists)
        }
        applyDefaultNames()
    }

    private func present(_ message: String) {
        errorMessage = message
        isErrorPresented = true
    }

    /// Name every key. With no default, that's the file's base name (all the same,
    /// per the "filename for all" rule) or a generic name for a clipboard paste;
    /// with a default, it overrides — numbered when there's more than one key.
    private func applyDefaultNames() {
        guard !drafts.isEmpty else { return }
        let base = defaultName.trimmingCharacters(in: .whitespaces).isEmpty
            ? (fileBaseName ?? "Imported key")
            : defaultName.trimmingCharacters(in: .whitespaces)
        for index in drafts.indices {
            drafts[index].name = drafts.count > 1 ? "\(base) \(index + 1)" : base
        }
    }

    /// The chosen file's name without extension, or nil for a clipboard paste.
    private var fileBaseName: String? {
        if case .file(let url) = source { return url.deletingPathExtension().lastPathComponent }
        return nil
    }

    private func applyDefaultStorage() {
        for index in drafts.indices { drafts[index].storage = defaultStorage }
    }

    /// Back to a clean slate: forget the source, the parsed keys, and every option.
    private func reset() {
        source = nil
        drafts = []
        defaultName = ""
        defaultStorage = .touchID
        defaultAuth = .biometryOrPasscode
        deleteFileAfter = false
        duplicatesRemoved = 0
    }

    // MARK: Importing

    private func startImport() {
        if willDeleteFile && droppedCount > 0 {
            showLossConfirmation = true
        } else {
            finishImport()
        }
    }

    /// Whether import will delete a source file — only for file imports with the
    /// toggle on (a clipboard paste has nothing to delete).
    private var willDeleteFile: Bool {
        if case .file = source, deleteFileAfter { return true }
        return false
    }

    private func finishImport() {
        do {
            let identities = try drafts
                .filter(\.include)
                .map { try AgeIdentity(importing: $0.key, label: $0.name, protection: $0.storage.keychainProtection(auth: defaultAuth)) }
            try model.importIdentities(identities)
            if willDeleteFile, case .file(let url) = source {
                try? FileManager.default.removeItem(at: url)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
