import Foundation
import CypherdexCore

/// UI-facing presentation helpers for identities, kept out of the core library.
extension AgeIdentity {
    var displayName: String {
        label.isEmpty ? defaultName : label
    }

    var defaultName: String {
        switch source {
        case .secureEnclave: return "Secure Enclave key"
        case .file(let url): return url.lastPathComponent
        case .memory: return "age key"
        }
    }

    var sourceIcon: String {
        switch source {
        case .secureEnclave: return "cpu"
        case .file: return "doc"
        case .memory: return "key"
        }
    }

    var sourceDescription: String {
        switch source {
        case .secureEnclave: return "Secure Enclave"
        case .file(let url): return url.path(percentEncoded: false)
        case .memory: return "Held in memory (this session only)"
        }
    }

    var kindDescription: String {
        switch material {
        case .x25519: return "age X25519"
        case .secureEnclave: return "Secure Enclave (P-256)"
        }
    }

    var accessControl: SecureEnclaveAccessControl? {
        if case .secureEnclave(_, let accessControl) = material { return accessControl }
        return nil
    }
}
