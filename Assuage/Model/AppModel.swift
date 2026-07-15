import Foundation
import AssuageCore

/// Per-window state: the panel selection, compose inputs, and sheet presentation
/// for one window. Each window has its own `AppModel`, so composing or opening a
/// file in one window never disturbs another. The shared key `library` is the
/// same object in every window, so all windows show and edit the same keys.
@MainActor
@Observable
final class AppModel {
    /// The primary panels — the kind of thing you're working on — shown in the
    /// sidebar on macOS and as tabs on iOS. Ordered most-used first.
    enum Panel: String, Hashable, CaseIterable, Identifiable {
        case files, text, notes, keys, people
        var id: Self { self }

        var title: String {
            switch self {
            case .files: return "Files"
            case .text: return "Text"
            case .notes: return "Notes"
            case .keys: return "Keys"
            case .people: return "Contacts"
            }
        }

        var systemImage: String {
            switch self {
            case .files: return "folder"
            case .text: return "text.alignleft"
            case .notes: return "note.text"
            case .keys: return "key"
            case .people: return "person.2"
            }
        }

        /// Whether this panel has Encrypt / Decrypt sub-tabs.
        var hasOperations: Bool { self == .files || self == .text }
    }

    /// The operation sub-tab within the Files and Text panels.
    enum Operation: String, CaseIterable, Identifiable {
        case encrypt, decrypt
        var id: Self { self }
        var title: String { self == .encrypt ? "Encrypt" : "Decrypt" }
        var systemImage: String { self == .encrypt ? "lock" : "lock.open" }
    }

    /// The Sign / Verify sub-tab within the Notes panel.
    enum NoteOperation: String, CaseIterable, Identifiable {
        case sign, verify
        var id: Self { self }
        var title: String { self == .sign ? "Sign" : "Verify" }
    }

    /// The kind of key shown in the Keys panel's sub-tabs.
    enum KeyCategory: String, CaseIterable, Identifiable {
        case encryption, signing
        var id: Self { self }
        var title: String { self == .encryption ? "Encryption" : "Signing" }
    }

    /// Whether a panel encrypts/decrypts to key recipients or a single passphrase.
    /// A scrypt (passphrase) stanza must be the sole recipient per the age spec,
    /// so the two are mutually exclusive.
    enum CredentialMode: String, CaseIterable, Identifiable {
        case keys, passphrase
        var id: Self { self }
    }

    /// The shared key library — the same instance across every window.
    let library: KeyLibrary

    init(library: KeyLibrary) {
        self.library = library
    }

    // MARK: Library (shared) — proxied so views keep using `model.…`

    /// Every identity the user holds. Reads through to the shared `library`, so a
    /// change in any window is reflected here.
    var identities: [AgeIdentity] { library.identities }

    /// Whether this Mac can create Secure Enclave keys.
    var secureEnclaveAvailable: Bool { library.secureEnclaveAvailable }

    @discardableResult
    func generateX25519(label: String, protection: KeychainProtection = .local) throws -> AgeIdentity {
        try library.generateX25519(label: label, protection: protection)
    }

    @available(macOS 26, *)
    @discardableResult
    func generatePostQuantum(label: String, protection: KeychainProtection = .local) throws -> AgeIdentity {
        try library.generatePostQuantum(label: label, protection: protection)
    }

    @discardableResult
    func generateSecureEnclave(label: String, accessControl: SecureEnclaveAccessControl) throws -> AgeIdentity {
        try library.generateSecureEnclave(label: label, accessControl: accessControl)
    }

    @available(macOS 26, *)
    @discardableResult
    func generateSecureEnclavePostQuantum(label: String, accessControl: SecureEnclaveAccessControl) throws -> AgeIdentity {
        try library.generateSecureEnclavePostQuantum(label: label, accessControl: accessControl)
    }

    // MARK: Signing keys (shared library)

    /// Every note-signing key the user holds.
    var signingKeys: [SigningKey] { library.signingKeys }

    /// The verifier keys the app trusts for verification (the user's own, for now).
    var verifierKeys: [VerifierKey] { library.verifierKeys }

    @discardableResult
    func generateSigningKey(name: String, protection: KeychainProtection = .local) throws -> SigningKey {
        try library.generateSigningKey(name: name, protection: protection)
    }

    func changeSignerProtection(of key: SigningKey, to protection: KeychainProtection) async throws {
        try await library.changeSignerProtection(of: key, to: protection)
    }

    func hydratedSigners(for keys: [SigningKey]) async throws -> [SigningKey] {
        try await library.hydratedSigners(for: keys)
    }

    /// Delete a signing key, then drop it from this window's selection.
    func deleteSigner(_ key: SigningKey) {
        library.deleteSigner(key)
        selectedKeyIDs.remove(key.id)
    }

    func copyVerifierKey(for key: SigningKey) { library.copyVerifierKey(for: key) }
    func exportVerifierKey(for key: SigningKey) { library.exportVerifierKey(for: key) }

    /// Hydrate a signing key's seed (prompting for Touch ID if it's protected) and
    /// save its private key as an encoded signer key (`PRIVATE+KEY+…`) for backup.
    /// The caller applies the soft export-auth gate first (see `SigningKeyRow`).
    func exportSigningKey(_ key: SigningKey) async throws {
        let hydrated = try await library.hydratedSigners(for: [key])
        guard let seeded = hydrated.first else { return }
        let identity = try seeded.signingIdentity()
        let base = key.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        SavePanel.save(text: identity.encodedSignerKey + "\n", suggestedName: "\(base)-signing-key.txt")
    }

    func importableKeys(at url: URL) throws -> [ImportableKey] {
        try library.importableKeys(at: url)
    }

    func importIdentities(_ identities: [AgeIdentity]) throws {
        try library.importIdentities(identities)
    }

    func hydratedSecrets(for identities: [AgeIdentity]) async throws -> [AgeIdentity] {
        try await library.hydratedSecrets(for: identities)
    }

    func rename(_ identity: AgeIdentity, to label: String) throws {
        try library.rename(identity, to: label)
    }

    func changeProtection(of identity: AgeIdentity, to protection: KeychainProtection, newLabel: String) async throws {
        try await library.changeProtection(of: identity, to: protection, newLabel: newLabel)
    }

    func recipientsFile(for identities: [AgeIdentity]) -> String {
        library.recipientsFile(for: identities)
    }

    func copyRecipients(for identities: [AgeIdentity]) {
        library.copyRecipients(for: identities)
    }

    func exportRecipients(for identities: [AgeIdentity]) {
        library.exportRecipients(for: identities)
    }

    /// Delete a key from the library, then drop it from this window's selections.
    func delete(_ identity: AgeIdentity) {
        library.delete(identity)
        encryptRecipientIDs.remove(identity.id)
        decryptIdentityIDs.remove(identity.id)
        selectedKeyIDs.remove(identity.id)
    }

    // MARK: Per-window UI state

    var selection: Panel = .files
    /// The Encrypt / Decrypt sub-tab for the Files and Text panels.
    var operation: Operation = .encrypt
    /// The Encryption / Signing sub-tab for the Keys panel.
    var keyCategory: KeyCategory = .encryption
    /// The Sign / Verify sub-tab for the Notes panel.
    var noteOperation: NoteOperation = .sign

    // Passphrase mode: kept here so it survives panel switches like the other
    // inputs. Cleared after a successful op (see the Encrypt/Decrypt views).
    var encryptMode: CredentialMode = .keys
    var decryptMode: CredentialMode = .keys
    var encryptPassphrase = ""
    var encryptPassphraseConfirm = ""
    var decryptPassphrase = ""

    /// Sheet presentation, driven from the menu bar as well as the Keys panel so
    /// the dialogs open in place from anywhere — no forced navigation to Keys.
    var showGenerateSheet = false
    var showGenerateSigningKeySheet = false
    var showImportSheet = false
    /// The signing key whose Edit sheet is open, if any.
    var editingSigner: SigningKey?
    /// An identity file to preload into the import sheet, set when one is opened
    /// from Finder. The sheet reads and clears it on appear.
    var pendingImportURL: URL?

    /// The selected keys in the Keys list, and the keys whose Edit / Export sheets
    /// are open. Selection lets the toolbar and menu act on the chosen keys; the
    /// sheet targets are set from the row, toolbar, or menu and presented at
    /// `ContentView`. Editing is single-key; export takes one or more.
    var selectedKeyIDs: Set<UUID> = []
    var editingKey: AgeIdentity?
    var exportingKeys: ExportRequest?

    /// The selected identities, in list order.
    var selectedKeys: [AgeIdentity] {
        identities.filter { selectedKeyIDs.contains($0.id) }
    }

    /// The lone selected identity, or nil when zero or several are selected.
    var singleSelectedKey: AgeIdentity? {
        selectedKeys.count == 1 ? selectedKeys.first : nil
    }

    /// The selected signing keys, in list order. The Keys list holds both kinds in
    /// one selection; this resolves the signing-key subset.
    var selectedSigners: [SigningKey] {
        signingKeys.filter { selectedKeyIDs.contains($0.id) }
    }

    /// The lone selected signing key, or nil when zero or several are selected.
    var singleSelectedSigner: SigningKey? {
        selectedSigners.count == 1 ? selectedSigners.first : nil
    }

    // Compose state, kept per-window so it survives panel switches and can be
    // populated by incoming system Services (see ServiceProvider) and the Keys panel.
    var encryptInput = ""
    var decryptInput = ""
    var queuedEncryptFiles: [URL] = []
    var queuedDecryptFiles: [URL] = []
    /// Identities selected as recipients on the Encrypt panel.
    var encryptRecipientIDs: Set<UUID> = []
    /// Ad-hoc recipients added on the Encrypt panel (pasted, or loaded from a file).
    var encryptExtraRecipients: [NamedRecipient] = []
    /// Which of `encryptExtraRecipients` are checked to actually encrypt to.
    var encryptExtraRecipientIDs: Set<String> = []
    /// Identities to try on the Decrypt panel.
    var decryptIdentityIDs: Set<UUID> = []
    /// Set when a "Check" service arrives so the Decrypt panel runs a check once.
    var autoCheckRequested = false
    /// Flipped by the Actions-menu ⌘↩ command to run the visible compose view's
    /// primary action; the active Encrypt / Decrypt / Sign view consumes it.
    var runComposeAction = false

    // Notes (Sign / Verify) compose state, kept per-window like the others.
    /// The note text being signed. When a signed note is pasted here, its signatures
    /// are pulled into `signKeptSignatures` and this is left holding just the text.
    var signInput = ""
    /// Signatures pulled out of a pasted note, offered to keep when re-signing.
    var signKeptSignatures: [SignedNote.Signature] = []
    /// The text those kept signatures were made over, to tell whether the text has
    /// since been edited (kept signatures are only valid while it hasn't).
    var signPastedText: String?
    /// Whether to keep the pasted signatures alongside the new ones.
    var keepOtherSignatures = true
    /// The signing keys chosen to sign with — the note gets one signature per key.
    var signIdentityIDs: Set<UUID> = []
    /// The signed note produced by the last Sign action.
    var signOutput: String?
    /// The note pasted into the Verify sub-tab.
    var verifyInput = ""

    /// Whether the kept signatures still match the current text (they're only valid
    /// while it's unchanged), so they can be retained on the next signature.
    var signTextUnchanged: Bool { signPastedText != nil && signInput == signPastedText }

    /// Sign `signInput` with every chosen key — one signature each — keeping the
    /// pasted signatures when the toggle is on and the text is unchanged. Hydrates
    /// the keys first as a batch, so a set of Touch ID–protected keys prompts once.
    /// Returns the serialized signed note.
    func signNote() async throws -> String {
        let chosen = signingKeys.filter { signIdentityIDs.contains($0.id) }
        guard !chosen.isEmpty else { throw AssuageError.noIdentities }
        let kept = (keepOtherSignatures && signTextUnchanged) ? signKeptSignatures : []
        let hydrated = try await library.hydratedSigners(for: chosen)
        var note = SignedNote(text: signInput, signatures: kept)
        for seeded in hydrated {
            try note.sign(with: seeded.signingIdentity(), keepingExisting: true)
        }
        return note.serialized
    }

    /// Prefill the Text panel to encrypt to these recipients.
    func composeEncrypt(to identities: [AgeIdentity]) {
        encryptRecipientIDs = Set(identities.map(\.id))
        encryptExtraRecipients = []
        encryptExtraRecipientIDs = []
        operation = .encrypt
        selection = .text
    }

    /// Prefill the Files or Text panel to encrypt to these ad-hoc recipients — the keys
    /// of a contact, all checked, with no owned identity pre-selected.
    func composeEncrypt(to recipients: [NamedRecipient], scope: ComposeScope) {
        encryptRecipientIDs = []
        encryptExtraRecipients = recipients
        encryptExtraRecipientIDs = Set(recipients.map(\.id))
        encryptMode = .keys
        operation = .encrypt
        selection = scope.panel
    }

    /// Prefill the Text panel to try these identities.
    func composeDecrypt(with identities: [AgeIdentity]) {
        decryptIdentityIDs = Set(identities.map(\.id))
        operation = .decrypt
        selection = .text
    }

    /// The id of the most recent request already routed into this window, so the
    /// several triggers that can deliver it (appear / focus / bus change) enqueue
    /// its files only once.
    private var lastHandledRequestID: ServiceRequest.ID?

    /// Route an incoming system Service / Finder request into this window's panels.
    /// Idempotent: a request already handled here is ignored, and files already
    /// queued aren't added again.
    func handle(_ request: ServiceRequest) {
        guard request.id != lastHandledRequestID else { return }
        lastHandledRequestID = request.id

        switch request.action {
        case .encrypt:
            operation = .encrypt
            if let text = request.text, !text.isEmpty { encryptInput = text }
            enqueue(request.files, into: &queuedEncryptFiles)
            selection = request.files.isEmpty ? .text : .files
        case .decrypt:
            operation = .decrypt
            if let text = request.text, !text.isEmpty { decryptInput = text }
            enqueue(request.files, into: &queuedDecryptFiles)
            selection = request.files.isEmpty ? .text : .files
        case .check:
            operation = .decrypt
            if let text = request.text, !text.isEmpty { decryptInput = text }
            enqueue(request.files, into: &queuedDecryptFiles)
            autoCheckRequested = true
            selection = request.files.isEmpty ? .text : .files
        case .importIdentities:
            // Preload the first file; the sheet takes one file (which may hold many
            // keys). Present the existing import flow.
            pendingImportURL = request.files.first
            selection = .keys
            showImportSheet = true
        }
    }

    /// Append only files not already queued, preserving order.
    private func enqueue(_ files: [URL], into queue: inout [URL]) {
        queue.append(contentsOf: files.filter { !queue.contains($0) })
    }
}
