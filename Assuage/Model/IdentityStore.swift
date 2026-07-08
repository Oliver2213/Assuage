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

/// Persists identities in the data-protection keychain as **two items per key**:
/// an unprotected *metadata* item and a separate *secret* item.
///
/// ## Why two items
/// On macOS, matching an access-controlled keychain item requires authentication
/// even when the query asks only for attributes (not `kSecValueData`) — the auth
/// is gated at the *item*, not its data. The auth-UI query flags spell this out:
/// `kSecUseAuthenticationUISkip` exists to *skip items that require authentication*
/// during a search, and `kSecUseAuthenticationUIFail` returns
/// `errSecInteractionNotAllowed` for such a match. (Confirmed empirically: an
/// attributes-only read of a `.userPresence` item returns -25308.) So keeping the
/// secret on the same item would make merely *listing* keys prompt. Splitting it
/// out lets `loadAll()` read only never-protected metadata items — no prompt —
/// while `secret(for:)` reads the protected secret on demand at decrypt/export,
/// which is the one place a prompt belongs.
///   - https://developer.apple.com/documentation/security/ksecuseauthenticationuiskip
///   - https://developer.apple.com/documentation/security/ksecuseauthenticationuifail
///
/// ## Keeping the pair consistent
/// - `save(_:)` writes the metadata first, then the secret, and rolls the metadata
///   back if the secret write fails. Because metadata is written first, a secret is
///   never left without its metadata; the only possible half-state (a crash between
///   the two writes) is a metadata item with no secret — public info only, no
///   secret material orphaned. Saves are add-only (new UUID each time; see `AppModel`).
/// - `delete(_:)` removes both items.
/// - `loadAll()` reconciles: it drops and cleans up any metadata whose secret is
///   *provably* missing. It can only probe keys whose secret isn't access-controlled
///   (local / synced) without prompting; authenticated keys are trusted to the
///   paired write/delete above.
///
/// Protection modes (see `KeychainProtection`) apply to the **secret** item:
/// - `.synced` — `AfterFirstUnlock` + `kSecAttrSynchronizable`, travels via iCloud.
/// - `.local` — `WhenUnlockedThisDeviceOnly`, device-bound, no auth.
/// - `.authenticated` — a `SecAccessControl` (biometry/passcode), so the secret is
///   released only after authentication and can't sync.
///
/// Secure Enclave keys have no secret item: their (enclave-encrypted) blob lives
/// in the metadata and is safe to hold.
///
/// Requires the **Keychain Sharing** capability — the data-protection keychain
/// needs a `keychain-access-groups` entitlement, otherwise writes fail with
/// `errSecMissingEntitlement`.
struct IdentityStore {
    /// Public metadata, one per identity, never access-controlled.
    private let metaService = "dev.smoll.Assuage.identities.meta"
    /// The raw X25519 secret, one per keychain key, access-controlled when protected.
    private let secretService = "dev.smoll.Assuage.identities.secret"

    /// List every stored identity from the metadata items alone. These carry no
    /// access control, so this never triggers an authentication prompt.
    func loadAll() -> [AgeIdentity] {
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
            .compactMap { try? decoder.decode(AgeIdentity.self, from: $0) }
            .filter { hasIntactSecret($0) }
            .sorted { $0.created < $1.created }
    }

    /// Whether an identity's secret is present, dropping the metadata if it's an
    /// orphan we can prove. Only local / synced keychain keys can be probed without
    /// a prompt; Secure Enclave keys (no secret item) and authenticated keys (a
    /// probe would prompt) are trusted to the paired save/delete and always kept.
    private func hasIntactSecret(_ identity: AgeIdentity) -> Bool {
        guard let protection = identity.keychainProtection, !protection.requiresAuthentication else {
            return true
        }
        switch secretStatus(account: identity.id.uuidString) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            // Orphaned metadata (e.g. a save that crashed mid-write) — clean it up.
            deleteItems(account: identity.id.uuidString, in: [metaService])
            return false
        default:
            // Ambiguous (e.g. a transient error) — keep it rather than risk deleting
            // a valid key's metadata and orphaning its secret.
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

    /// Save (or replace) an identity: an unprotected metadata item plus, for
    /// keychain (X25519) keys, a secret item guarded per its protection. The
    /// secret must be present on `identity` (it is at generation/import time).
    func save(_ identity: AgeIdentity) throws {
        let synced = identity.isSynced
        // Metadata: the identity with its secret blanked. Always readable.
        let metadata = try JSONEncoder().encode(identity.withKeychainSecret(""))
        try upsert(service: metaService, account: identity.id.uuidString,
                   data: metadata, accessControl: nil, synced: synced, label: identity.displayName)

        guard let secret = identity.x25519Secret else { return } // SE keys keep no secret item
        let accessControl: SecAccessControl?
        if case .authenticated(let auth) = identity.keychainProtection {
            accessControl = try makeAccessControl(auth)
        } else {
            accessControl = nil
        }
        do {
            try upsert(service: secretService, account: identity.id.uuidString,
                       data: Data(secret.utf8), accessControl: accessControl, synced: synced, label: identity.displayName)
        } catch {
            // Don't leave a metadata item with no secret behind it.
            deleteItems(account: identity.id.uuidString, in: [metaService])
            throw error
        }
    }

    /// Update an identity's metadata in place — e.g. a rename. Touches only the
    /// unprotected metadata item, so no secret is read and it never prompts. The
    /// protection (and thus the item's key attributes) is unchanged, so the upsert
    /// matches and updates the existing item.
    ///
    /// Note: the secret item's `kSecAttrLabel` (shown in the Touch ID prompt) is
    /// left as-is to avoid touching the protected item; a later protection change
    /// re-adds it with the current label.
    func updateMetadata(_ identity: AgeIdentity) throws {
        let metadata = try JSONEncoder().encode(identity.withKeychainSecret(""))
        try upsert(service: metaService, account: identity.id.uuidString,
                   data: metadata, accessControl: nil, synced: identity.isSynced, label: identity.displayName)
    }

    /// Fetch a keychain (X25519) key's secret from its secret item. For
    /// `.authenticated` keys this prompts for Touch ID / passcode; pass a shared
    /// `LAContext` across a batch so one prompt covers them all. Throws on cancel.
    nonisolated func secret(for identity: AgeIdentity, context: LAContext) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: identity.id.uuidString,
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

    func delete(_ identity: AgeIdentity) {
        deleteItems(account: identity.id.uuidString, in: [metaService, secretService])
    }

    /// Rewrite an identity's items under a (possibly new) protection. The secret
    /// and synchronizable/access-control attributes are part of how each item is
    /// stored, so a protection change can't be an in-place update — remove the old
    /// items (whatever their sync state) and write fresh. The secret must be
    /// present on `identity`.
    func replace(_ identity: AgeIdentity) throws {
        delete(identity)
        try save(identity)
    }

    // MARK: Helpers

    /// Add or update one generic-password item.
    private func upsert(service: String, account: String, data: Data,
                        accessControl: SecAccessControl?, synced: Bool, label: String) throws {
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

    /// Build the access control for a hardware-protected key: the secret is
    /// wrapped by the Secure Enclave and released only after authentication.
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
