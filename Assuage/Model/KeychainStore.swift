import Foundation
import Security
import LocalAuthentication
import AssuageCore

/// A keychain operation that failed, carrying the underlying `OSStatus` so the
/// failure is surfaced instead of silently swallowed.
struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Couldn’t reach the keychain: \(detail)"
    }
}

/// A record `KeychainStore` can persist: something with a stable id, a public
/// metadata face, and (unless it has no extractable secret) a guarded secret.
///
/// Both age identities and note-signing keys conform, so they share one storage
/// implementation — there's a single place that gets the keychain semantics right.
protocol KeychainStorable: Codable, Identifiable, Sendable where ID == UUID {
    /// The item label shown in the keychain and in Touch ID prompts.
    var displayName: String { get }
    /// Used only to order the loaded list.
    var created: Date { get }
    /// Whether the secret may sync via iCloud Keychain.
    var isSynced: Bool { get }
    /// The protection guarding the secret, or `nil` when there is no secret item —
    /// e.g. a Secure Enclave key whose (device-bound) blob rides in the metadata.
    var storageProtection: KeychainProtection? { get }
    /// The secret to store, or `nil` when there is none, or it isn't hydrated.
    var keychainSecret: String? { get }
    /// The metadata item's `kSecAttrDescription` ("Kind").
    var metaDescription: String { get }
    /// The secret item's `kSecAttrDescription` ("Kind").
    var secretDescription: String { get }
    /// A copy with the secret blanked, for the (always-readable) metadata item.
    func blankingSecret() -> Self
    /// A copy carrying `secret`, for hydration.
    func settingSecret(_ secret: String) -> Self
}

/// Persists `KeychainStorable` records in the data-protection keychain as **two
/// items per record**: an unprotected *metadata* item and a separate *secret* item.
///
/// ## Why two items
/// On macOS, matching an access-controlled keychain item requires authentication
/// even when the query asks only for attributes (not `kSecValueData`) — the auth
/// is gated at the *item*, not its data. The auth-UI query flags spell this out:
/// `kSecUseAuthenticationUISkip` exists to *skip items that require authentication*
/// during a search, and `kSecUseAuthenticationUIFail` returns
/// `errSecInteractionNotAllowed` for such a match. (Confirmed empirically: an
/// attributes-only read of a `.userPresence` item returns -25308.) So keeping the
/// secret on the same item would make merely *listing* records prompt. Splitting it
/// out lets `loadAll()` read only never-protected metadata items — no prompt —
/// while `secret(for:)` reads the protected secret on demand at decrypt/sign/export,
/// which is the one place a prompt belongs.
///   - https://developer.apple.com/documentation/security/ksecuseauthenticationuiskip
///   - https://developer.apple.com/documentation/security/ksecuseauthenticationuifail
///
/// ## Keeping the pair consistent
/// - `save(_:)` writes the metadata first, then the secret, and rolls the metadata
///   back if the secret write fails. Because metadata is written first, a secret is
///   never left without its metadata; the only possible half-state (a crash between
///   the two writes) is a metadata item with no secret — public info only.
/// - `delete(_:)` removes both items.
/// - `loadAll()` reconciles: it drops any metadata whose secret is *provably*
///   missing. It can only probe records whose secret isn't access-controlled (local
///   / synced) without prompting; authenticated records are trusted to the paired
///   write/delete above.
///
/// Records with no secret item (`storageProtection == nil`, e.g. Secure Enclave
/// keys) keep their device-bound blob in the metadata, which is safe to hold.
///
/// Requires the **Keychain Sharing** capability — the data-protection keychain
/// needs a `keychain-access-groups` entitlement, otherwise writes fail with
/// `errSecMissingEntitlement`.
struct KeychainStore<Record: KeychainStorable> {
    /// Public metadata, one per record, never access-controlled.
    let metaService: String
    /// The secret, one per record, access-controlled when protected.
    let secretService: String

    /// List every stored record from the metadata items alone. These carry no
    /// access control, so this never triggers an authentication prompt.
    func loadAll() -> [Record] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: metaService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else {
            return []
        }
        let decoder = JSONDecoder()
        return items
            .compactMap { try? decoder.decode(Record.self, from: $0) }
            .filter { hasIntactSecret($0) }
            .sorted { $0.created < $1.created }
    }

    /// Whether a record's secret is present, dropping the metadata if it's an orphan
    /// we can prove. Only local / synced secrets can be probed without a prompt;
    /// records with no secret item and authenticated records (a probe would prompt)
    /// are trusted to the paired save/delete and always kept.
    private func hasIntactSecret(_ record: Record) -> Bool {
        guard let protection = record.storageProtection, !protection.requiresAuthentication else {
            return true
        }
        switch secretStatus(account: record.id.uuidString) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            deleteItems(account: record.id.uuidString, in: [metaService])
            return false
        default:
            return true
        }
    }

    /// Existence check for a secret item, reading no data. Safe (prompt-free) only
    /// for non-access-controlled secrets — the caller guarantees that.
    private func secretStatus(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }

    /// Save (or replace) a record: an unprotected metadata item plus, unless it has
    /// no secret item, a secret item guarded per its protection. The secret must be
    /// present on `record` when there's a secret item (it is at generation/import).
    func save(_ record: Record) throws {
        let synced = record.isSynced
        let metadata = try JSONEncoder().encode(record.blankingSecret())
        try upsert(service: metaService, account: record.id.uuidString,
                   data: metadata, accessControl: nil, synced: synced,
                   label: record.displayName, description: record.metaDescription)

        // No secret item for records that don't have one (e.g. Secure Enclave).
        guard let protection = record.storageProtection else { return }
        guard let secret = record.keychainSecret else {
            deleteItems(account: record.id.uuidString, in: [metaService])
            throw KeychainError(status: errSecParam)
        }
        let accessControl: SecAccessControl?
        if case .authenticated(let auth) = protection {
            accessControl = try makeAccessControl(auth)
        } else {
            accessControl = nil
        }
        do {
            try upsert(service: secretService, account: record.id.uuidString,
                       data: Data(secret.utf8), accessControl: accessControl, synced: synced,
                       label: record.displayName, description: record.secretDescription)
        } catch {
            // Don't leave a metadata item with no secret behind it.
            deleteItems(account: record.id.uuidString, in: [metaService])
            throw error
        }
    }

    /// Update a record's metadata in place — e.g. a rename. Touches only the
    /// unprotected metadata item, so no secret is read and it never prompts.
    func updateMetadata(_ record: Record) throws {
        let metadata = try JSONEncoder().encode(record.blankingSecret())
        try upsert(service: metaService, account: record.id.uuidString,
                   data: metadata, accessControl: nil, synced: record.isSynced,
                   label: record.displayName, description: record.metaDescription)
    }

    /// Fetch a record's secret from its secret item. For `.authenticated` records
    /// this prompts for Touch ID / passcode; pass a shared `LAContext` across a batch
    /// so one prompt covers them all. Throws on cancel.
    nonisolated func secret(for record: Record, context: LAContext) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: record.id.uuidString,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return secret
    }

    func delete(_ record: Record) {
        deleteItems(account: record.id.uuidString, in: [metaService, secretService])
    }

    /// Rewrite a record's items under a (possibly new) protection. The secret and
    /// sync/access-control attributes are part of how each item is stored, so a
    /// protection change can't be an in-place update — remove the old items and
    /// write fresh. The secret must be present on `record`.
    func replace(_ record: Record) throws {
        delete(record)
        try save(record)
    }

    // MARK: Helpers

    /// Add or update one generic-password item. `description` sets the item's "Kind"
    /// (`kSecAttrDescription`) so it's self-describing — this material isn't a
    /// keychain-native key type, so it's stored as a generic password.
    private func upsert(service: String, account: String, data: Data,
                        accessControl: SecAccessControl?, synced: Bool, label: String, description: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synced,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrDescription as String: description,
        ]
        if let accessControl {
            attributes[kSecAttrAccessControl as String] = accessControl
        } else {
            attributes[kSecAttrAccessible as String] = synced
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let addStatus = SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
        default:
            throw KeychainError(status: addStatus)
        }
    }

    private func deleteItems(account: String, in services: [String]) {
        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Build the access control for a hardware-protected key: the secret is wrapped
    /// by the Secure Enclave and released only after authentication.
    private func makeAccessControl(_ auth: KeychainAuth) throws -> SecAccessControl {
        let flags: SecAccessControlCreateFlags
        switch auth {
        case .biometryOrPasscode: flags = [.userPresence]
        case .currentBiometry: flags = [.biometryCurrentSet]
        }
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &error
        ) else {
            throw KeychainError(status: errSecParam)
        }
        return accessControl
    }
}

// MARK: - Conformances

extension AgeIdentity: KeychainStorable {
    var storageProtection: KeychainProtection? { keychainProtection }
    // Secure Enclave keys keep no separate secret; their blob rides in the metadata.
    var metaDescription: String { keychainProtection == nil ? "age Secure Enclave key" : "age identity (public)" }
    var secretDescription: String { "age private key" }
    func blankingSecret() -> AgeIdentity { withKeychainSecret("") }
    func settingSecret(_ secret: String) -> AgeIdentity { withKeychainSecret(secret) }
}

extension SigningKey: KeychainStorable {
    var storageProtection: KeychainProtection? { protection }
    var metaDescription: String { "note signer (public)" }
    var secretDescription: String { "note signing key" }
    func blankingSecret() -> SigningKey { withSeed("") }
    func settingSecret(_ secret: String) -> SigningKey { withSeed(secret) }
}
