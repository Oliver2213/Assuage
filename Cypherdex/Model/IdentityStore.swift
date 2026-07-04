import Foundation
import Security
import LocalAuthentication
import CypherdexCore

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
/// The split is what keeps launch prompt-free. Reading an access-controlled
/// item — even just its attributes — triggers its Touch ID / passcode check, so
/// keeping the secret in the same item would make merely *listing* keys prompt.
/// Instead `loadAll()` reads only the metadata items (never access-controlled),
/// and `secret(for:)` reads the secret item on demand, which is the one place a
/// prompt is expected.
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
    private let metaService = "dev.smoll.Cypherdex.identities.meta"
    /// The raw X25519 secret, one per keychain key, access-controlled when protected.
    private let secretService = "dev.smoll.Cypherdex.identities.secret"
    /// The pre-split single-item location, kept only so `purgeLegacyItems` can clear it.
    private let legacyService = "dev.smoll.Cypherdex.identities"

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
            .sorted { $0.created < $1.created }
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

    /// Remove every item at the pre-split single-item location. Those held the
    /// secret alongside the metadata, so they'd both be unreadable by `loadAll()`
    /// now and prompt when merely matched. A blanket delete needs no read, so it
    /// never prompts. New-format items live under different services.
    func purgeLegacyItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func delete(_ identity: AgeIdentity) {
        deleteItems(account: identity.id.uuidString, in: [metaService, secretService])
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
