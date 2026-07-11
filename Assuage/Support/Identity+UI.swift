import Foundation
import AssuageCore

/// UI-facing presentation helpers for identities, kept out of the core library.
extension AgeIdentity {
    var displayName: String {
        label.isEmpty ? defaultName : label
    }

    var defaultName: String {
        if material.kind == .sshEd25519 { return "SSH key" }
        switch source {
        case .secureEnclave: return "Secure Enclave key"
        case .keychain: return "age key"
        }
    }

    var sourceIcon: String {
        if material.kind == .sshEd25519 { return "terminal" }
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

    var kindDescription: String { material.kind.description }
}
