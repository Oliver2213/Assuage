import Foundation
import CypherdexCore

/// UI-facing presentation helpers for identities, kept out of the core library.
extension AgeIdentity {
    var displayName: String {
        label.isEmpty ? defaultName : label
    }

    var defaultName: String {
        if case .sshEd25519 = material { return "SSH key" }
        switch source {
        case .secureEnclave: return "Secure Enclave key"
        case .keychain: return "age key"
        }
    }

    var sourceIcon: String {
        if case .sshEd25519 = material { return "terminal" }
        switch keychainProtection {
        case .synced: return "icloud"
        case .local: return "key"
        case .authenticated: return "touchid"
        case nil: return "cpu" // Secure Enclave
        }
    }

    var sourceDescription: String {
        switch keychainProtection {
        case .synced: return "Keychain · Synced via iCloud"
        case .local: return "Keychain · This device only"
        case .authenticated(let auth): return "Keychain · \(auth.displayName), this device"
        case nil: return "Secure Enclave"
        }
    }

    var kindDescription: String {
        switch material {
        case .x25519: return "age X25519"
        case .secureEnclave: return "Secure Enclave (P-256)"
        case .sshEd25519: return "SSH (Ed25519)"
        }
    }

    var accessControl: SecureEnclaveAccessControl? {
        if case .secureEnclave(_, let accessControl) = material { return accessControl }
        return nil
    }
}
