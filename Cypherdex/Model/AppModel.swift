import Foundation
import CypherdexCore

/// App-wide state: the panel selection and the user's identities (age keypairs).
///
/// Identities are session-only for now — export the ones you want to keep. Keychain
/// persistence is the next step.
@MainActor
@Observable
final class AppModel {
    /// The primary panels, shown in the sidebar.
    enum Panel: String, Hashable, CaseIterable, Identifiable {
        case encrypt, decrypt, keys
        var id: Self { self }

        var title: String {
            switch self {
            case .encrypt: return "Encrypt"
            case .decrypt: return "Decrypt"
            case .keys: return "Keys"
            }
        }

        var systemImage: String {
            switch self {
            case .encrypt: return "lock"
            case .decrypt: return "lock.open"
            case .keys: return "key"
            }
        }
    }

    var selection: Panel? = .encrypt
    var identities: [AgeIdentity] = []

    /// Whether this Mac can create Secure Enclave keys.
    var secureEnclaveAvailable: Bool { SecureEnclaveKeys.isAvailable }

    @discardableResult
    func generateX25519(label: String) -> AgeIdentity {
        let identity = AgeIdentity.generateX25519(label: label)
        identities.append(identity)
        return identity
    }

    @discardableResult
    func generateSecureEnclave(
        label: String,
        accessControl: SecureEnclaveAccessControl
    ) throws -> AgeIdentity {
        let identity = try AgeIdentity.generateSecureEnclave(label: label, accessControl: accessControl)
        identities.append(identity)
        return identity
    }

    func importIdentityFile(at url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var imported = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("AGE-SECRET-KEY-1") else { continue }
            let identity = try AgeIdentity(
                importingX25519: trimmed,
                label: url.deletingPathExtension().lastPathComponent,
                storedAt: url
            )
            identities.append(identity)
            imported += 1
        }
        if imported == 0 { throw CypherdexError.unrecognizedIdentity(url.lastPathComponent) }
    }

    func delete(_ identity: AgeIdentity) {
        identities.removeAll { $0.id == identity.id }
    }
}
