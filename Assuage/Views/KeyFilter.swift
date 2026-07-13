import AssuageCore

/// A quick-select category for the identity table's "Select All" menu, grouping
/// keys by a notable capability.
enum KeyFilter: CaseIterable, Identifiable {
    case postQuantum
    case secureEnclave
    case postQuantumSecureEnclave

    var id: Self { self }

    var title: String {
        switch self {
        case .postQuantum: return "Post-quantum"
        case .secureEnclave: return "Secure Enclave"
        case .postQuantumSecureEnclave: return "Post-quantum · Secure Enclave"
        }
    }

    func matches(_ identity: AgeIdentity) -> Bool {
        switch identity.material.kind {
        case .postQuantum: return self == .postQuantum
        case .secureEnclavePostQuantum: return true // post-quantum and Secure Enclave
        case .secureEnclaveP256: return self == .secureEnclave
        case .x25519, .sshEd25519: return false
        }
    }

    /// The categories that match at least one of `identities`.
    static func available(in identities: [AgeIdentity]) -> [KeyFilter] {
        allCases.filter { filter in identities.contains(where: filter.matches) }
    }
}
