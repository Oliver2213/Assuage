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

/// Persists identities in the data-protection keychain — one generic-password
/// item each, with the public **metadata** in `kSecAttrGeneric` and the **secret**
/// in the item's data field.
///
/// Splitting them lets `loadAll()` list every key by reading attributes only
/// (`kSecReturnData: false`), so it never prompts — even for hardware-protected
/// keys whose secret would otherwise require Touch ID. The secret is fetched
/// lazily by `secret(for:)` at decrypt/export time, which is where the prompt
/// belongs.
///
/// Protection modes (see `KeychainProtection`):
/// - `.synced` — `AfterFirstUnlock` + `kSecAttrSynchronizable`, travels via iCloud.
/// - `.local` — `WhenUnlockedThisDeviceOnly`, device-bound, readable while unlocked.
/// - `.authenticated` — a `SecAccessControl` (biometry/passcode), so the secret is
///   released only after authentication and can't sync.
///
/// Requires the **Keychain Sharing** capability — the data-protection keychain
/// needs a `keychain-access-groups` entitlement, otherwise writes fail with
/// `errSecMissingEntitlement`.
struct IdentityStore {
    private let service = "dev.smoll.Cypherdex.identities"

    /// List every stored identity from metadata alone — no secret is read, so
    /// this never triggers an authentication prompt.
    func loadAll() -> [AgeIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: false,
            kSecReturnAttributes as String: true,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        let decoder = JSONDecoder()
        return items
            .compactMap { $0[kSecAttrGeneric as String] as? Data }
            .compactMap { try? decoder.decode(AgeIdentity.self, from: $0) }
            .sorted { $0.created < $1.created }
    }

    /// Save (or replace) an identity. The secret must be present on `identity`
    /// (it is at generation/import time). Throws `KeychainError` if the keychain
    /// rejects the write, so callers can tell the user instead of losing the key.
    func save(_ identity: AgeIdentity) throws {
        // Metadata copy with the secret blanked — this is what we list at launch.
        let metadata = try JSONEncoder().encode(identity.withKeychainSecret(""))
        let secret = Data((identity.x25519Secret ?? "").utf8)
        let synced = identity.isSynced

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecAttrSynchronizable as String: synced,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var attributes: [String: Any] = [
            kSecAttrGeneric as String: metadata,
            kSecValueData as String: secret,
            // The system auth prompt shows this label ("…use “My Laptop”…").
            kSecAttrLabel as String: identity.displayName,
        ]
        if case .authenticated(let auth) = identity.keychainProtection {
            attributes[kSecAttrAccessControl as String] = try makeAccessControl(auth)
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

    /// Fetch a keychain (X25519) key's secret. For `.authenticated` keys this
    /// prompts for Touch ID / passcode; pass a shared `LAContext` across a batch
    /// so one prompt covers them all. Throws `KeychainError` on failure or cancel.
    nonisolated func secret(for identity: AgeIdentity, context: LAContext) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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
