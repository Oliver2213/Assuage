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
        case files, text, keys
        var id: Self { self }

        var title: String {
            switch self {
            case .files: return "Files"
            case .text: return "Text"
            case .keys: return "Keys"
            }
        }

        var systemImage: String {
            switch self {
            case .files: return "folder"
            case .text: return "text.alignleft"
            case .keys: return "key"
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
    var showImportSheet = false
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

    // Compose state, kept per-window so it survives panel switches and can be
    // populated by incoming system Services (see ServiceProvider) and the Keys panel.
    var encryptInput = ""
    var decryptInput = ""
    var queuedEncryptFiles: [URL] = []
    var queuedDecryptFiles: [URL] = []
    /// Identities selected as recipients on the Encrypt panel.
    var encryptRecipientIDs: Set<UUID> = []
    /// Ad-hoc recipients pasted on the Encrypt panel.
    var encryptExtraRecipients: [AgeRecipient] = []
    /// Identities to try on the Decrypt panel.
    var decryptIdentityIDs: Set<UUID> = []
    /// Set when a "Check" service arrives so the Decrypt panel runs a check once.
    var autoCheckRequested = false
    /// Flipped by the Actions-menu ⌘↩ command to run the visible compose view's
    /// primary action; the active Encrypt / Decrypt view consumes it.
    var runComposeAction = false

    /// Prefill the Text panel to encrypt to these recipients.
    func composeEncrypt(to identities: [AgeIdentity]) {
        encryptRecipientIDs = Set(identities.map(\.id))
        encryptExtraRecipients = []
        operation = .encrypt
        selection = .text
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
