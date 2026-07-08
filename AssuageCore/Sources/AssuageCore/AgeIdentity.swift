import Foundation
import AgeKit

/// The private-key material behind an identity.
///
/// *Where* the secret lives is encoded in the case itself, so an identity can
/// never claim a location it doesn't actually have (no nullable "secret" field
/// paired with a separate "source" flag that could disagree).
public enum IdentityMaterial: Sendable, Hashable, Codable {
    /// A native age X25519 secret key (`AGE-SECRET-KEY-1…`), which is exportable and
    /// works with any age tool. The secret lives in the keychain; `protection`
    /// records where it's stored and whether it's authentication-gated.
    ///
    /// `secretKey` may be empty for an identity loaded from the keychain but not
    /// yet unlocked — the app hydrates it on demand (see `withKeychainSecret`).
    case x25519(secretKey: String, protection: KeychainProtection)

    /// A Secure Enclave key (`AGE-PLUGIN-SE-1…`): device-bound and non-exportable.
    /// The identity string encodes the enclave key blob; `accessControl` records the
    /// presence policy it was created with. Enclave keys never sync — the blob is
    /// only usable on the Mac that generated it.
    case secureEnclave(identity: String, accessControl: SecureEnclaveAccessControl)

    /// An imported SSH Ed25519 key. We keep only the 32-byte Ed25519 `seed`
    /// (base64) — enough to rebuild the key, decrypt, and re-export it (any
    /// passphrase is consumed at import). Storage-wise it behaves exactly like an
    /// X25519 secret: it lives in the keychain and `protection` guards it.
    ///
    /// `seed` may be empty for an identity loaded from the keychain but not yet
    /// unlocked — the app hydrates it on demand (see `withKeychainSecret`).
    case sshEd25519(seed: String, protection: KeychainProtection)
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
        case .x25519(_, let protection), .sshEd25519(_, let protection):
            return .keychain(synced: protection.isSynced)
        case .secureEnclave:
            return .secureEnclave
        }
    }

    /// The storage protection for a keychain key (X25519 or SSH), or `nil` for
    /// Secure Enclave keys.
    public var keychainProtection: KeychainProtection? {
        switch material {
        case .x25519(_, let protection), .sshEd25519(_, let protection): return protection
        case .secureEnclave: return nil
        }
    }

    /// Whether this identity's secret may sync to the user's other devices.
    /// Only keychain keys (X25519 or SSH) can sync; Secure Enclave keys never do.
    public var isSynced: Bool {
        switch material {
        case .x25519(_, let protection), .sshEd25519(_, let protection): return protection.isSynced
        case .secureEnclave: return false
        }
    }

    /// Whether using this identity to decrypt prompts for presence (Touch ID /
    /// passcode) — true for Secure Enclave keys and authentication-gated
    /// keychain keys.
    public var requiresPresence: Bool {
        switch material {
        case .x25519(_, let protection), .sshEd25519(_, let protection):
            return protection.requiresAuthentication
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
    /// - Parameter protection: where the secret is stored and how it's guarded.
    ///   Defaults to `.local` (this device, no authentication).
    public static func generateX25519(label: String = "", protection: KeychainProtection = .local, created: Date = Date()) -> AgeIdentity {
        let identity = Age.X25519Identity.generate()
        return AgeIdentity(
            id: UUID(),
            label: label,
            created: created,
            material: .x25519(secretKey: identity.string, protection: protection),
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
        protection: KeychainProtection = .local
    ) throws {
        let identity = try Self.parseX25519(secretKey)
        self.init(
            id: UUID(),
            label: label,
            created: created,
            material: .x25519(secretKey: identity.string, protection: protection),
            recipient: AgeRecipient(kind: .x25519, encoding: identity.recipient.string)
        )
    }

    /// The raw X25519 secret if present, else `nil`. X25519-specific; used by
    /// the age-format export path (SSH keys export as OpenSSH, not an age secret).
    public var x25519Secret: String? {
        if case .x25519(let secret, _) = material, !secret.isEmpty { return secret }
        return nil
    }

    /// The keychain secret string for any keychain-backed key — the
    /// `AGE-SECRET-KEY-1…` for X25519, or the base64 Ed25519 seed for SSH — else
    /// `nil` (Secure Enclave keys, or a key loaded but not yet hydrated). This is
    /// the accessor the store uses to persist and probe the secret item.
    public var keychainSecret: String? {
        switch material {
        case .x25519(let secret, _), .sshEd25519(let secret, _): return secret.isEmpty ? nil : secret
        case .secureEnclave: return nil
        }
    }

    /// A copy of this keychain identity with its secret filled in, for use right
    /// before decrypting or exporting. A no-op for Secure Enclave keys.
    public func withKeychainSecret(_ secret: String) -> AgeIdentity {
        let filled: IdentityMaterial
        switch material {
        case .x25519(_, let protection): filled = .x25519(secretKey: secret, protection: protection)
        case .sshEd25519(_, let protection): filled = .sshEd25519(seed: secret, protection: protection)
        case .secureEnclave: return self
        }
        return AgeIdentity(id: id, label: label, created: created, material: filled, recipient: recipient)
    }

    /// A copy of this keychain identity re-protected under a new `KeychainProtection`,
    /// carrying the given secret. Used when moving a key between local / synced /
    /// authenticated storage. A no-op for Secure Enclave keys.
    public func withKeychainProtection(_ protection: KeychainProtection, secretKey: String) -> AgeIdentity {
        let reprotected: IdentityMaterial
        switch material {
        case .x25519: reprotected = .x25519(secretKey: secretKey, protection: protection)
        case .sshEd25519: reprotected = .sshEd25519(seed: secretKey, protection: protection)
        case .secureEnclave: return self
        }
        return AgeIdentity(id: id, label: label, created: created, material: reprotected, recipient: recipient)
    }

    /// Import an SSH Ed25519 identity from an OpenSSH private key. Passphrase-
    /// protected keys need `passphrase`; only the 32-byte seed is retained, so no
    /// passphrase is ever needed again. The derived public recipient is the key's
    /// `authorized_keys` line.
    ///
    /// - Throws: `SSHKeyError.passphraseRequired` / `.incorrectPassphrase` for
    ///   protected keys, `SSHKeyError.unsupportedKeyType` for non-Ed25519 keys.
    public init(
        importingSSHEd25519 pem: String,
        passphrase: String? = nil,
        label: String = "",
        created: Date = Date(),
        protection: KeychainProtection = .local
    ) throws {
        let identity: Age.SSHEd25519Identity
        do {
            identity = try Age.SSHEd25519Identity(opensshPEM: pem, passphrase: passphrase)
        } catch let error as SSHKeyError {
            throw CypherdexError(sshKeyError: error, context: pem)
        }
        self.init(
            id: UUID(),
            label: label,
            created: created,
            material: .sshEd25519(seed: Data(identity.seed).base64EncodedString(), protection: protection),
            recipient: AgeRecipient(kind: .sshEd25519, encoding: identity.authorizedKey)
        )
    }

    /// Rebuild the AgeKit SSH identity from a stored base64 seed.
    static func parseSSHEd25519(seed: String) throws -> Age.SSHEd25519Identity {
        guard let data = Data(base64Encoded: seed) else { throw CypherdexError.unrecognizedIdentity(seed) }
        do {
            return try Age.SSHEd25519Identity(seed: Array(data))
        } catch {
            throw CypherdexError.unrecognizedIdentity(seed)
        }
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
        case .sshEd25519(let seed, _):
            return try Self.parseSSHEd25519(seed: seed)
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
    /// The full identity rendered the way age renders a generated key: a comment
    /// header naming the `generator` app, the creation date, the public key, then
    /// the private key on its own line. Suitable for writing to an identity file.
    ///
    /// - Parameter generator: the app producing the file, written into the first
    ///   comment line. Defaults to `"age"`; the app passes its own name so the
    ///   core stays free of any app branding.
    public func ageFormatted(generator: String = "age") -> String {
        var lines: [String] = []
        lines.append("# \(generator) identity")
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
        case .sshEd25519(let seed, _):
            // Export as a real OpenSSH private key (which age/rage accept via -i),
            // reconstructed from the stored seed.
            if let identity = try? Self.parseSSHEd25519(seed: seed) {
                lines.append(identity.opensshPEM())
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

}

extension Sequence where Element == AgeIdentity {
    /// A recipients file: each identity's public recipient on its own line — the
    /// plain format age reads with `-R`, and that Cypherdex re-imports. With
    /// `includeNames`, a labeled key is preceded by a `# label` comment for the
    /// humans reading it; unlabeled keys have none. age ignores comment lines.
    ///
    /// Public material only — safe to share.
    public func recipientsFile(includeNames: Bool) -> String {
        var lines: [String] = []
        for identity in self {
            if includeNames, !identity.label.isEmpty {
                lines.append("# \(identity.label)")
            }
            lines.append(identity.recipient.encoding)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}
