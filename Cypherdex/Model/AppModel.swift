import Foundation
import LocalAuthentication
import CypherdexCore

/// App-wide state: the panel selection and the user's identities (age keypairs).
///
/// Identities persist in the keychain (see `IdentityStore`): X25519 keys locally,
/// synced via iCloud Keychain, or hardware-protected behind Touch ID; Secure
/// Enclave keys are always device-local. Keychain secrets are loaded lazily —
/// `hydratedSecrets(for:)` fetches them just before decrypt/export.
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

    var selection: Panel? = .encrypt
    var identities: [AgeIdentity] = []

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

    // Compose state, kept here so it survives panel switches and can be populated
    // by incoming system Services (see ServiceProvider) and by the Keys panel.
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

    private let store = IdentityStore()

    init() {
        // Sweep out pre-split single-blob items so they don't linger unreadable.
        store.purgeLegacyItems()
        identities = store.loadAll()
    }

    /// Route an incoming system Service request into the right panel.
    func handle(_ request: ServiceRequest) {
        switch request.action {
        case .encrypt:
            if let text = request.text, !text.isEmpty { encryptInput = text }
            queuedEncryptFiles.append(contentsOf: request.files)
            selection = .encrypt
        case .decrypt:
            if let text = request.text, !text.isEmpty { decryptInput = text }
            queuedDecryptFiles.append(contentsOf: request.files)
            selection = .decrypt
        case .check:
            if let text = request.text, !text.isEmpty { decryptInput = text }
            queuedDecryptFiles.append(contentsOf: request.files)
            autoCheckRequested = true
            selection = .decrypt
        }
    }

    /// Whether this Mac can create Secure Enclave keys.
    var secureEnclaveAvailable: Bool { SecureEnclaveKeys.isAvailable }

    @discardableResult
    func generateX25519(label: String, protection: KeychainProtection = .local) throws -> AgeIdentity {
        let identity = AgeIdentity.generateX25519(label: label, protection: protection)
        try add(identity)
        return identity
    }

    @discardableResult
    func generateSecureEnclave(
        label: String,
        accessControl: SecureEnclaveAccessControl
    ) throws -> AgeIdentity {
        let identity = try AgeIdentity.generateSecureEnclave(label: label, accessControl: accessControl)
        try add(identity)
        return identity
    }

    /// Append an identity and persist it. If the keychain rejects the write we
    /// roll the in-memory list back and rethrow, so the UI never shows a key that
    /// wouldn't survive a relaunch.
    private func add(_ identity: AgeIdentity) throws {
        identities.append(identity)
        do {
            try store.save(identity)
        } catch {
            identities.removeAll { $0.id == identity.id }
            throw error
        }
    }

    /// Read an identity file and return the X25519 keys it contains, ready to be
    /// reviewed and named before import. Throws if the file has no importable keys.
    func importableKeys(at url: URL) throws -> [ImportableKey] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let keys = AgeIdentity.importableKeys(from: text)
        if keys.isEmpty { throw CypherdexError.unrecognizedIdentity(url.lastPathComponent) }
        return keys
    }

    /// Commit reviewed keys to the store. All-or-nothing per key: if a save fails
    /// the already-added keys stay, and the error is rethrown so the UI can report it.
    func importIdentities(_ identities: [AgeIdentity]) throws {
        for identity in identities {
            try add(identity)
        }
    }

    /// Fetch the secrets for keychain identities so they can decrypt or export.
    /// Runs off the main actor (the fetch blocks while an auth prompt is up), and
    /// shares one `LAContext` so a batch of protected keys asks for Touch ID once.
    /// Secure Enclave keys pass through unchanged (they unlock at use).
    func hydratedSecrets(for identities: [AgeIdentity]) async throws -> [AgeIdentity] {
        let store = self.store
        return try await Task.detached {
            let context = LAContext()
            context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration
            return try identities.map { identity in
                // Only keychain keys need hydration, and only if not already loaded.
                guard identity.keychainProtection != nil, identity.x25519Secret == nil else {
                    return identity
                }
                let secret = try store.secret(for: identity, context: context)
                return identity.withKeychainSecret(secret)
            }
        }.value
    }

    func delete(_ identity: AgeIdentity) {
        identities.removeAll { $0.id == identity.id }
        encryptRecipientIDs.remove(identity.id)
        decryptIdentityIDs.remove(identity.id)
        store.delete(identity)
    }
}
