/// The key type new keys start on in the generate sheet, chosen in Settings.
/// Post-quantum needs macOS 26, so the Settings picker is shown only there.
enum DefaultKeyType: String, CaseIterable, Identifiable {
    /// A standard age key (X25519, or P-256 in the Secure Enclave).
    case standard
    /// Software post-quantum — X-Wing, keychain-backed.
    case postQuantumSoftware
    /// Hardware post-quantum — ML-KEM-768 + P-256, sealed in the Secure Enclave.
    case postQuantumSecureEnclave

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .postQuantumSoftware: return "Post-quantum (software)"
        case .postQuantumSecureEnclave: return "Post-quantum (Secure Enclave)"
        }
    }

    var isPostQuantum: Bool { self != .standard }
}
