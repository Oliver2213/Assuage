import Foundation
import Security
import CypherdexCore

/// Persists identities — including their secrets — in the data-protection
/// keychain. One generic-password item per identity, value = JSON of the
/// identity. `ThisDeviceOnly` so keys never sync off the Mac.
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

    func save(_ identity: AgeIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        }
    }

    func delete(_ identity: AgeIdentity) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id.uuidString,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
