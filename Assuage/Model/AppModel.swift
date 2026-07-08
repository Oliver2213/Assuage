import Foundation
import AssuageCore

/// Per-window state: the panel selection, compose inputs, and sheet presentation
/// for one window. Each window has its own `AppModel`, so composing or opening a
/// file in one window never disturbs another. The shared key `library` is the
/// same object in every window, so all windows show and edit the same keys.
@MainActor
@Observable
final class AppModel {
    /// The primary panels, shown in the sidebar.
    enum Panel: String, Hashable, CaseIterable, Identifiable {
        case encrypt, decrypt, keys
        var id: Self { self }

        var title: String {
            switch self {
            case .encrypt: return "Encrypt"
            case .decrypt: return "Decrypt"
            case .keys: return "Keys"
            }
        }

        var systemImage: String {
            switch self {
            case .encrypt: return "lock"
            case .decrypt: return "lock.open"
            case .keys: return "key"
            }
        }
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

    @discardableResult
    func generateSecureEnclave(label: String, accessControl: SecureEnclaveAccessControl) throws -> AgeIdentity {
        try library.generateSecureEnclave(label: label, accessControl: accessControl)
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

    var selection: Panel? = .encrypt

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

    /// Prefill the Encrypt panel to encrypt to a single recipient.
    func composeEncrypt(to identity: AgeIdentity) {
        encryptRecipientIDs = [identity.id]
        encryptExtraRecipients = []
        selection = .encrypt
    }

    /// Prefill the Decrypt panel to try a single identity.
    func composeDecrypt(with identity: AgeIdentity) {
        decryptIdentityIDs = [identity.id]
        selection = .decrypt
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
            if let text = request.text, !text.isEmpty { encryptInput = text }
            enqueue(request.files, into: &queuedEncryptFiles)
            selection = .encrypt
        case .decrypt:
            if let text = request.text, !text.isEmpty { decryptInput = text }
            enqueue(request.files, into: &queuedDecryptFiles)
            selection = .decrypt
        case .check:
            if let text = request.text, !text.isEmpty { decryptInput = text }
            enqueue(request.files, into: &queuedDecryptFiles)
            autoCheckRequested = true
            selection = .decrypt
        }
    }

    /// Append only files not already queued, preserving order.
    private func enqueue(_ files: [URL], into queue: inout [URL]) {
        queue.append(contentsOf: files.filter { !queue.contains($0) })
    }
}
