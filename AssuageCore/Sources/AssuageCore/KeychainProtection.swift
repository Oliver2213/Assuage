/// How a keychain (X25519) key's secret is stored and guarded at rest.
///
/// Only `synced` keys can travel via iCloud Keychain; both `local` and
/// `authenticated` keys stay on the Mac (device-only accessibility can't sync,
/// and access-controlled items can't sync at all).
public enum KeychainProtection: Sendable, Hashable, Codable {
    /// iCloud Keychain — available on the user's other devices. Not auth-gated.
    case synced

    /// This device only. Readable whenever the login keychain is unlocked, with
    /// no authentication — i.e. it sits decryptable in the keychain while unlocked.
    case local

    /// This device only, wrapped by the Secure Enclave. The secret is released
    /// only after a successful `KeychainAuth`, so it isn't decryptable at rest
    /// even while the keychain is unlocked. Cannot sync.
    case authenticated(KeychainAuth)

    /// Whether the secret may travel to the user's other devices.
    public var isSynced: Bool { self == .synced }

    /// Whether reading the secret prompts for authentication.
    public var requiresAuthentication: Bool {
        if case .authenticated = self { return true }
        return false
    }
}
