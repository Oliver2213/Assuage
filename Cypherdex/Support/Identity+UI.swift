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
        case .keychain: return "age key"
        }
    }

    var sourceIcon: String {
        switch source {
        case .secureEnclave: return "cpu"
        case .keychain(let synced): return synced ? "icloud" : "key"
        }
    }

    var sourceDescription: String {
        switch source {
        case .secureEnclave: return "Secure Enclave"
        case .keychain(let synced):
            return synced ? "Keychain · Synced via iCloud" : "Keychain · This device only"
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
