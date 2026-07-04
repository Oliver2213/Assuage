import Foundation
import Security
import CypherdexCore

/// A keychain operation that failed, carrying the underlying `OSStatus` so the
/// failure is surfaced instead of silently swallowed.
struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Couldn’t save to the keychain: \(detail)"
    }
}

/// Persists identities — including their secrets — in the data-protection
/// keychain. One generic-password item per identity, value = JSON of the
/// identity.
///
/// Non-synced keys use `ThisDeviceOnly` accessibility so they never leave the
/// Mac. Keys the user marked as synced use `AfterFirstUnlock` (device-only
/// accessibility can't sync) and set `kSecAttrSynchronizable`, so they travel
/// via iCloud Keychain. Secure Enclave keys are always device-local.
///
/// Requires the **Keychain Sharing** capability — the data-protection keychain
/// needs a `keychain-access-groups` entitlement, otherwise every write fails
/// with `errSecMissingEntitlement`.
struct IdentityStore {
    private let service = "dev.smoll.Cypherdex.identities"

    func loadAll() -> [AgeIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecUseDataProtectionKeychain as String: true,
            // Return both local and iCloud-synced items.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        let decoder = JSONDecoder()
        return items
            .compactMap { $0[kSecValueData as String] as? Data }
            .compactMap { try? decoder.decode(AgeIdentity.self, from: $0) }
            .sorted { $0.created < $1.created }
    }

    /// Save (or replace) an identity. Throws `KeychainError` if the keychain
    /// rejects the write, so callers can tell the user instead of losing the key.
    func save(_ identity: AgeIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let synced = identity.isSynced
        // `kSecAttrSynchronizable` and `kSecAttrService`/`kSecAttrAccount` form the
        // primary key, so the query must match on synchronizable to find an existing
        // item to update.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecAttrSynchronizable as String: synced,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Device-only accessibility cannot sync, so synced items relax it.
            kSecAttrAccessible as String: synced
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
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

    func delete(_ identity: AgeIdentity) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecUseDataProtectionKeychain as String: true,
            // Match local or synced so either can be removed.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
