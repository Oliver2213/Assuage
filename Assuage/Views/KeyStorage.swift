import AssuageCore

/// Where a key lives and how it's guarded — one ordered ladder from most portable
/// to most locked-down, shared by every place that offers a storage choice (the
/// Generate, Edit, and Import sheets) so they all read the same. The underlying
/// algorithm is derived rather than chosen: the keychain rows are X25519 (or X-Wing
/// when post-quantum), and the Secure Enclave row is a native P-256 key (or
/// ML-KEM-768 + P-256 when post-quantum).
enum KeyStorage: String, CaseIterable, Identifiable {
    case synced, thisDevice, touchID, secureEnclave
    var id: Self { self }

    var title: String {
        switch self {
        case .synced: return "Synced across your devices (iCloud)"
        case .thisDevice: return "This device only"
        case .touchID: return "This device · Touch ID"
        case .secureEnclave: return "Secure Enclave · this Mac, not exportable (P-256)"
        }
    }

    /// Whether this row asks for authentication (and shows a "Require" picker).
    var isAuthenticated: Bool { self == .touchID || self == .secureEnclave }

    /// The keychain rows only — the choices when re-protecting an existing keychain
    /// key. An enclave key can't move to the keychain, or vice-versa.
    static var keychainCases: [KeyStorage] { [.synced, .thisDevice, .touchID] }

    /// The keychain protection for the non-enclave rows.
    func keychainProtection(auth: KeychainAuth) -> KeychainProtection {
        switch self {
        case .synced: return .synced
        case .thisDevice: return .local
        case .touchID: return .authenticated(auth)
        case .secureEnclave: return .local // unused: enclave keys take a different path
        }
    }

    /// The keychain row matching an existing protection, or `nil` for an enclave key.
    init?(keychainProtection: KeychainProtection?) {
        switch keychainProtection {
        case .synced: self = .synced
        case .local: self = .thisDevice
        case .authenticated: self = .touchID
        case nil: return nil
        }
    }
}
