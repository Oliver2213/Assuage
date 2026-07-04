/// The authentication a hardware-protected keychain key requires before the
/// keychain will release its secret. Maps to `SecAccessControlCreateFlags`
/// (the mapping itself lives in the app's keychain layer).
public enum KeychainAuth: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// Touch ID with a passcode fallback (`.userPresence`). Survives biometry
    /// changes — adding or removing a fingerprint doesn't invalidate the key.
    case biometryOrPasscode

    /// Touch ID tied to the *current* fingerprint set (`.biometryCurrentSet`).
    /// Strongest, but enrolling or removing any fingerprint permanently
    /// invalidates the key, so the secret can no longer be read.
    case currentBiometry

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .biometryOrPasscode: return "Touch ID or passcode"
        case .currentBiometry: return "Touch ID (current fingerprints)"
        }
    }
}
