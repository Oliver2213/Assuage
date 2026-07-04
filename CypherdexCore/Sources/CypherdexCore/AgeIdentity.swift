import Foundation
import AgeKit

/// The private-key material behind an identity.
///
/// *Where* the secret lives is encoded in the case itself, so an identity can
/// never claim a location it doesn't actually have (no nullable "secret" field
/// paired with a separate "source" flag that could disagree).
public enum IdentityMaterial: Sendable, Hashable, Codable {
    /// A native age X25519 secret key (`AGE-SECRET-KEY-1…`), which is exportable and
    /// works with any age tool. The secret lives in the keychain; `synced` records
    /// whether it may travel to the user's other devices via iCloud Keychain
    /// (`false` = this device only).
    case x25519(secretKey: String, synced: Bool)

    /// A Secure Enclave key (`AGE-PLUGIN-SE-1…`): device-bound and non-exportable.
    /// The identity string encodes the enclave key blob; `accessControl` records the
    /// presence policy it was created with. Enclave keys never sync — the blob is
    /// only usable on the Mac that generated it.
    case secureEnclave(identity: String, accessControl: SecureEnclaveAccessControl)
}

/// An age identity (private key) the app can decrypt with, plus the metadata age
/// records when generating one: when it was created, a human description, and
/// where its secret lives.
public struct AgeIdentity: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    /// A human-facing description shown in the UI and written as a comment on export.
    public var label: String
    public let created: Date
    public let material: IdentityMaterial
    /// The public recipient derived from this identity — always in sync with the secret.
    public let recipient: AgeRecipient

    /// Where the private key lives. Derived from `material`, never stored separately.
    public enum Source: Sendable, Hashable {
        /// Stored in the keychain. `synced` is true when it may sync via iCloud Keychain.
        case keychain(synced: Bool)
        case secureEnclave
    }

    public var source: Source {
        switch material {
        case .x25519(_, let synced):
            return .keychain(synced: synced)
        case .secureEnclave:
            return .secureEnclave
        }
    }

    /// Whether this identity's secret may sync to the user's other devices.
    /// Only keychain (X25519) keys can sync; Secure Enclave keys never do.
    public var isSynced: Bool {
        if case .x25519(_, let synced) = material { return synced }
        return false
    }

    /// Whether using this identity to decrypt prompts for presence (Touch ID / passcode).
    public var requiresPresence: Bool {
        switch material {
        case .x25519: return false
        case .secureEnclave(_, let accessControl): return accessControl.requiresPresence
        }
    }

    init(id: UUID, label: String, created: Date, material: IdentityMaterial, recipient: AgeRecipient) {
        self.id = id
        self.label = label
        self.created = created
        self.material = material
        self.recipient = recipient
    }
}

// MARK: - Creating identities

extension AgeIdentity {
    /// Generate a fresh age X25519 identity, stored in the keychain.
    ///
    /// - Parameter synced: whether the secret may sync to the user's other devices
    ///   via iCloud Keychain. Defaults to `false` (this device only).
    public static func generateX25519(label: String = "", synced: Bool = false, created: Date = Date()) -> AgeIdentity {
        let identity = Age.X25519Identity.generate()
        return AgeIdentity(
            id: UUID(),
            label: label,
            created: created,
            material: .x25519(secretKey: identity.string, synced: synced),
            recipient: AgeRecipient(kind: .x25519, encoding: identity.recipient.string)
        )
    }

    /// Import an identity from an `AGE-SECRET-KEY-1…` secret key string.
    ///
    /// - Throws: `CypherdexError.unrecognizedIdentity` if the string isn't a valid
    ///   X25519 secret key.
    public init(
        importingX25519 secretKey: String,
        label: String = "",
        created: Date = Date(),
        synced: Bool = false
    ) throws {
        let identity = try Self.parseX25519(secretKey)
        self.init(
            id: UUID(),
            label: label,
            created: created,
            material: .x25519(secretKey: identity.string, synced: synced),
            recipient: AgeRecipient(kind: .x25519, encoding: identity.recipient.string)
        )
    }

    /// Parse an X25519 secret key via AgeKit's public identity parser (the string
    /// initialiser on `X25519Identity` isn't public).
    static func parseX25519(_ secretKey: String) throws -> Age.X25519Identity {
        // `parseIdentities` reads line-by-line and expects a trailing newline.
        let data = Data((secretKey.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8)
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        let identities: [any Identity]
        do {
            identities = try Age.parseIdentities(input: input)
        } catch {
            throw CypherdexError.unrecognizedIdentity(secretKey)
        }
        guard let x25519 = identities.first as? Age.X25519Identity else {
            throw CypherdexError.unrecognizedIdentity(secretKey)
        }
        return x25519
    }

    /// The AgeKit identity used to unwrap the file key during decryption.
    func makeAgeIdentity() throws -> any Identity {
        switch material {
        case .x25519(let secret, _):
            return try Self.parseX25519(secret)
        case .secureEnclave(let identity, _):
            let privateKey = try SecureEnclaveKeys.loadPrivateKey(ageIdentity: identity)
            return SecureEnclaveIdentity(privateKey: privateKey)
        }
    }

    /// Generate a new Secure Enclave identity on this Mac.
    ///
    /// - Throws: `CypherdexError.secureEnclaveUnavailable` on Macs without a Secure Enclave.
    public static func generateSecureEnclave(
        label: String = "",
        accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode,
        created: Date = Date()
    ) throws -> AgeIdentity {
        let generated = try SecureEnclaveKeys.generate(accessControl: accessControl)
        return AgeIdentity(
            id: UUID(),
            label: label,
            created: created,
            material: .secureEnclave(identity: generated.identity, accessControl: accessControl),
            recipient: AgeRecipient(kind: .secureEnclave, encoding: generated.recipient)
        )
    }
}

// MARK: - Export

extension AgeIdentity {
    private static let appName = "Cypherdex"

    /// The full identity rendered the way age renders a generated key: a comment
    /// header with the creation date, a comment with the public key, then the
    /// private key on its own line. Suitable for writing to an identity file.
    public func ageFormatted() -> String {
        var lines: [String] = []
        lines.append("# \(Self.appName) age identity")
        if !label.isEmpty {
            lines.append("# label: \(label)")
        }
        lines.append("# created: \(created.ISO8601Format())")
        if case .secureEnclave(_, let accessControl) = material {
            lines.append("# access control: \(accessControl.ageLabel)")
        }
        lines.append("# public key: \(recipient.encoding)")
        switch material {
        case .x25519(let secret, _):
            lines.append(secret)
        case .secureEnclave(let identity, _):
            lines.append(identity)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Just the public recipient, with a short identifying comment. Safe to share.
    public func publicKeyFile() -> String {
        var lines = ["# \(Self.appName) recipient"]
        if !label.isEmpty {
            lines.append("# label: \(label)")
        }
        lines.append(recipient.encoding)
        return lines.joined(separator: "\n") + "\n"
    }
}
