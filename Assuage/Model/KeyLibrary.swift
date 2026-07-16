import Foundation
import LocalAuthentication
import AssuageCore

/// The user's key library: the age identities (keypairs) and every operation on
/// them. Shared across all windows via a single instance in the environment, so
/// every window shows and edits the same set of keys.
///
/// Identities persist in the keychain (see `KeychainStore`): X25519 keys locally,
/// synced via iCloud Keychain, or hardware-protected behind Touch ID; Secure
/// Enclave keys are always device-local. Keychain secrets are loaded lazily —
/// `hydratedSecrets(for:)` fetches them just before decrypt/export.
@MainActor
@Observable
final class KeyLibrary {
    /// Every identity the user holds. Mutated only through the methods below so it
    /// stays in sync with the keychain.
    private(set) var identities: [AgeIdentity] = []

    /// Every note-signing key the user holds. Kept alongside the age identities but
    /// separate — a signing key has no age recipient and never encrypts or decrypts.
    private(set) var signingKeys: [SigningKey] = []

    private let store = KeychainStore<AgeIdentity>(
        metaService: "dev.smoll.Assuage.identities.meta",
        secretService: "dev.smoll.Assuage.identities.secret")
    /// The one shared library, used by every window and by the note-signing /
    /// verification Services (which run without a specific window).
    static let shared = KeyLibrary()

    private let signerStore = KeyLibrary.makeSignerStore()

    /// The signing-key keychain store, shared with the note-signing Service so the
    /// two read the exact same items (see `NoteSigningService`).
    static func makeSignerStore() -> KeychainStore<SigningKey> {
        KeychainStore<SigningKey>(
            metaService: "dev.smoll.Assuage.signers.meta",
            secretService: "dev.smoll.Assuage.signers.secret")
    }

    init() {
        identities = store.loadAll()
        signingKeys = signerStore.loadAll()
    }

    /// Whether this Mac can create Secure Enclave keys.
    var secureEnclaveAvailable: Bool { SecureEnclaveKeys.isAvailable }

    @discardableResult
    func generateX25519(label: String, protection: KeychainProtection = .local) throws -> AgeIdentity {
        let identity = AgeIdentity.generateX25519(label: label, protection: protection)
        try add(identity)
        return identity
    }

    /// Generate a post-quantum (X-Wing) key, stored in the keychain like an X25519
    /// key. Requires macOS 26 (CryptoKit's X-Wing KEM).
    @available(macOS 26, *)
    @discardableResult
    func generatePostQuantum(label: String, protection: KeychainProtection = .local) throws -> AgeIdentity {
        let identity = try AgeIdentity.generatePostQuantum(label: label, protection: protection)
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

    /// Generate a hardware post-quantum key (Secure Enclave ML-KEM-768 + P-256).
    /// Requires macOS 26.
    @available(macOS 26, *)
    @discardableResult
    func generateSecureEnclavePostQuantum(label: String, accessControl: SecureEnclaveAccessControl) throws -> AgeIdentity {
        let identity = try AgeIdentity.generateSecureEnclavePostQuantum(label: label, accessControl: accessControl)
        try add(identity)
        return identity
    }

    /// Append an identity and persist it. If the keychain rejects the write we
    /// roll the in-memory list back and rethrow, so the UI never shows a key that
    /// wouldn't survive a relaunch.
    private func add(_ identity: AgeIdentity) throws {
        // Persist first; on failure nothing is added to the in-memory list.
        try store.save(identity)
        // Then keep only a secret-less copy in memory — exactly what `loadAll`
        // returns — so a freshly generated or imported key's private half doesn't
        // linger, and every operation re-hydrates it from the keychain on demand.
        // That closes the gap where a just-created authenticated key could be used
        // once without a Touch ID prompt. (A no-op for Secure Enclave keys, which
        // hold no extractable secret.)
        identities.append(identity.withKeychainSecret(""))
    }

    /// Read an identity file and return the keys it contains, ready to be reviewed
    /// and named before import. Throws if the file has no importable keys.
    func importableKeys(at url: URL) throws -> [ImportableKey] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let keys = AgeIdentity.importableKeys(from: text)
        if keys.isEmpty { throw AssuageError.unrecognizedIdentity(url.lastPathComponent) }
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
                // Uses keychainSecret (not x25519Secret) so SSH and post-quantum keys
                // aren't needlessly re-fetched — which for authenticated keys would
                // re-prompt for Touch ID.
                guard identity.keychainProtection != nil, identity.keychainSecret == nil else {
                    return identity
                }
                let secret = try store.secret(for: identity, context: context)
                return identity.withKeychainSecret(secret)
            }
        }.value
    }

    /// Rename an identity (label only). Persists to the metadata item without
    /// touching the secret, so it never prompts, and works for every key type.
    func rename(_ identity: AgeIdentity, to label: String) throws {
        guard let index = identities.firstIndex(where: { $0.id == identity.id }) else { return }
        var renamed = identity
        renamed.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.updateMetadata(renamed)
        identities[index] = renamed
    }

    /// Move a keychain (X25519) key to a new protection (local / synced / Touch
    /// ID), optionally renaming it in the same step. Reads the current secret —
    /// which prompts if the key is currently Touch ID–protected — off the main
    /// actor so the prompt doesn't block the UI, then rewrites both items under the
    /// new class. Not valid for Secure Enclave keys.
    func changeProtection(of identity: AgeIdentity, to protection: KeychainProtection, newLabel: String) async throws {
        let store = self.store
        // Only the secret read can prompt; run it off-main so the sheet stays live.
        let secret = try await Task.detached {
            try store.secret(for: identity, context: LAContext())
        }.value
        var updated = identity.withKeychainProtection(protection, secretKey: secret)
        updated.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.replace(updated)
        if let index = identities.firstIndex(where: { $0.id == identity.id }) {
            // Keep the secret out of the in-memory model, as loadAll would.
            identities[index] = updated.withKeychainSecret("")
        }
    }

    /// Remove an identity from the library and the keychain.
    func delete(_ identity: AgeIdentity) {
        identities.removeAll { $0.id == identity.id }
        store.delete(identity)
    }

    // MARK: Signing keys

    /// The verifier keys for every signing key the user holds — the trust source we
    /// have today, so a note the user signed shows as verified.
    var verifierKeys: [VerifierKey] { signingKeys.compactMap(\.verifierKey) }

    @discardableResult
    func generateSigningKey(name: String, protection: KeychainProtection = .local) throws -> SigningKey {
        let key = try SigningKey.generate(name: name, protection: protection)
        try addSigner(key)
        return key
    }

    /// Persist a signing key, then keep only a seedless copy in memory — matching
    /// how `add` handles age keys, so a freshly made authenticated key can't be used
    /// once without its Touch ID prompt.
    private func addSigner(_ key: SigningKey) throws {
        try signerStore.save(key)
        signingKeys.append(key.withSeed(""))
    }

    /// Move a signing key to a new protection (local / synced / Touch ID). Reads the
    /// seed — prompting if it's currently Touch ID–protected — off the main actor,
    /// then rewrites both items. The name (and thus the verifier key) is unchanged.
    func changeSignerProtection(of key: SigningKey, to protection: KeychainProtection) async throws {
        let signerStore = self.signerStore
        let seed = try await Task.detached {
            try signerStore.secret(for: key, context: LAContext())
        }.value
        let updated = key.withProtection(protection, seed: seed)
        try signerStore.replace(updated)
        if let index = signingKeys.firstIndex(where: { $0.id == key.id }) {
            signingKeys[index] = updated.withSeed("")
        }
    }

    func deleteSigner(_ key: SigningKey) {
        signingKeys.removeAll { $0.id == key.id }
        signerStore.delete(key)
    }

    /// Copy a signing key's public verifier key to the clipboard.
    func copyVerifierKey(for key: SigningKey) {
        Pasteboard.copy(key.verifierKeyEncoding, sensitive: false)
    }

    /// Save a signing key's public verifier key to a file.
    func exportVerifierKey(for key: SigningKey) {
        let base = key.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        SavePanel.save(text: key.verifierKeyEncoding + "\n", suggestedName: "\(base)-verifier.txt")
    }

    /// Fetch the seeds for signing keys so they can sign or export. Runs off the
    /// main actor (the fetch blocks while an auth prompt is up) and shares one
    /// `LAContext` so a batch of protected keys asks for Touch ID once.
    func hydratedSigners(for keys: [SigningKey]) async throws -> [SigningKey] {
        let signerStore = self.signerStore
        return try await Task.detached {
            let context = LAContext()
            context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration
            return try keys.map { key in
                guard key.keychainSecret == nil else { return key }
                let secret = try signerStore.secret(for: key, context: context)
                return key.withSeed(secret)
            }
        }.value
    }

    // MARK: Recipients (public keys)

    /// The recipients file for these identities, honoring the "include names"
    /// preference. Public material, so no auth or hydration is needed.
    func recipientsFile(for identities: [AgeIdentity]) -> String {
        let includeNames = UserDefaults.standard.bool(forKey: PreferenceKeys.recipientCommentLabels)
        return identities.recipientsFile(includeNames: includeNames)
    }

    /// Copy the recipients file for these identities to the clipboard.
    func copyRecipients(for identities: [AgeIdentity]) {
        guard !identities.isEmpty else { return }
        Pasteboard.copy(recipientsFile(for: identities), sensitive: false)
    }

    /// Save the recipients file for these identities. A single key suggests a
    /// `.pub` name; a set suggests a combined recipients file.
    func exportRecipients(for identities: [AgeIdentity]) {
        guard !identities.isEmpty else { return }
        let name: String
        if identities.count == 1 {
            let base = identities[0].displayName.replacingOccurrences(of: " ", with: "-")
            name = "\(base).pub"
        } else {
            name = "\(AppInfo.name)-Recipients.txt"
        }
        SavePanel.save(text: recipientsFile(for: identities), suggestedName: name)
    }
}
