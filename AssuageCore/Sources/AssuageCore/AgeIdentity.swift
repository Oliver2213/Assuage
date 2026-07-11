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

    /// A hardware post-quantum key (an `AGE-PLUGIN-SE-1…` whose payload holds an
    /// ML-KEM-768 and a P-256 enclave blob), forming an `age1tagpq…`
    /// (`mlkem768p256tag`) recipient. Device-bound, never synced, and its private
    /// halves stay in the enclave — like `secureEnclave`, but quantum-secure. The
    /// encoding is age-plugin-se's, so these keys import/export between the two tools.
    case secureEnclavePostQuantum(identity: String, accessControl: SecureEnclaveAccessControl)

    /// An imported SSH Ed25519 key. We keep only the 32-byte Ed25519 `seed`
    /// (base64) — enough to rebuild the key, decrypt, and re-export it (any
    /// passphrase is consumed at import). Storage-wise it behaves exactly like an
    /// X25519 secret: it lives in the keychain and `protection` guards it.
    ///
    /// `seed` may be empty for an identity loaded from the keychain but not yet
    /// unlocked — the app hydrates it on demand (see `withKeychainSecret`).
    case sshEd25519(seed: String, protection: KeychainProtection)

    /// A native age post-quantum X-Wing secret key (`AGE-SECRET-KEY-PQ-1…`),
    /// exportable and usable with age 1.3+. Storage-wise it behaves exactly like
    /// `x25519`: the secret lives in the keychain and `protection` records where
    /// it's stored and whether it's authentication-gated.
    ///
    /// `secretKey` may be empty for an identity loaded from the keychain but not
    /// yet unlocked — the app hydrates it on demand (see `withKeychainSecret`).
    case postQuantum(secretKey: String, protection: KeychainProtection)
}

// MARK: - Capability axes
//
// The material has two independent axes: *where* it's stored (which governs
// protection, syncing, and presence) and *what kind* of key it is (which governs
// the crypto, recipient type, and label). Every derived property reads one of
// these, so adding a key type means updating only `storage`, `kind`, the crypto in
// `makeAgeIdentity`, and `withKeychain` — not a dozen scattered switches.

extension IdentityMaterial {
    /// Where a key lives and how it's guarded.
    public enum Storage: Sendable, Hashable {
        case keychain(KeychainProtection)
        case secureEnclave(SecureEnclaveAccessControl)

        var source: AgeIdentity.Source {
            switch self {
            case .keychain(let protection): return .keychain(synced: protection.isSynced)
            case .secureEnclave: return .secureEnclave
            }
        }
        var keychainProtection: KeychainProtection? {
            if case .keychain(let protection) = self { return protection }
            return nil
        }
        var accessControl: SecureEnclaveAccessControl? {
            if case .secureEnclave(let accessControl) = self { return accessControl }
            return nil
        }
        var isSynced: Bool { keychainProtection?.isSynced ?? false }
        var requiresPresence: Bool {
            switch self {
            case .keychain(let protection): return protection.requiresAuthentication
            case .secureEnclave(let accessControl): return accessControl.requiresPresence
            }
        }
    }

    /// The key algorithm — the parts that genuinely differ per type.
    public enum Kind: Sendable, Hashable {
        case x25519, sshEd25519, postQuantum              // keychain-backed
        case secureEnclaveP256, secureEnclavePostQuantum   // enclave-backed

        /// A human-facing description of the key type.
        public var description: String {
            switch self {
            case .x25519: return "age X25519"
            case .sshEd25519: return "SSH (Ed25519)"
            case .postQuantum: return "age post-quantum (X-Wing)"
            case .secureEnclaveP256: return "Secure Enclave (P-256)"
            case .secureEnclavePostQuantum: return "Secure Enclave post-quantum (ML-KEM-768 + P-256)"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .x25519: return .x25519
        case .sshEd25519: return .sshEd25519
        case .postQuantum: return .postQuantum
        case .secureEnclave: return .secureEnclaveP256
        case .secureEnclavePostQuantum: return .secureEnclavePostQuantum
        }
    }

    public var storage: Storage {
        switch self {
        case .x25519(_, let p), .sshEd25519(_, let p), .postQuantum(_, let p): return .keychain(p)
        case .secureEnclave(_, let a), .secureEnclavePostQuantum(_, let a): return .secureEnclave(a)
        }
    }

    /// The string this case stores: a keychain secret for keychain keys, or the
    /// enclave identity blob for enclave keys. (May be empty when not yet hydrated.)
    var stored: String {
        switch self {
        case .x25519(let s, _), .sshEd25519(let s, _), .postQuantum(let s, _),
             .secureEnclave(let s, _), .secureEnclavePostQuantum(let s, _):
            return s
        }
    }

    /// Rebuild this material as a keychain key with a new secret and protection.
    /// Enclave keys are returned unchanged — their private key can't be re-secreted.
    func withKeychain(secret: String, protection: KeychainProtection) -> IdentityMaterial {
        switch self {
        case .x25519: return .x25519(secretKey: secret, protection: protection)
        case .sshEd25519: return .sshEd25519(seed: secret, protection: protection)
        case .postQuantum: return .postQuantum(secretKey: secret, protection: protection)
        case .secureEnclave, .secureEnclavePostQuantum: return self
        }
    }
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

    /// Where the private key lives (keychain vs Secure Enclave).
    public var source: Source { material.storage.source }

    /// The storage protection for a keychain key, or `nil` for enclave keys.
    public var keychainProtection: KeychainProtection? { material.storage.keychainProtection }

    /// The Secure Enclave access control for an enclave key, or `nil` otherwise.
    public var accessControl: SecureEnclaveAccessControl? { material.storage.accessControl }

    /// Whether this identity's secret may sync to the user's other devices — only
    /// keychain keys can; enclave keys never do.
    public var isSynced: Bool { material.storage.isSynced }

    /// Whether decrypting with this identity prompts for presence (Touch ID /
    /// passcode) — true for enclave keys and authentication-gated keychain keys.
    public var requiresPresence: Bool { material.storage.requiresPresence }

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
    /// - Throws: `AssuageError.unrecognizedIdentity` if the string isn't a valid
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
        guard material.storage.keychainProtection != nil else { return nil } // enclave keys keep no secret item
        return material.stored.isEmpty ? nil : material.stored
    }

    /// A copy of this keychain identity with its secret filled in, for use right
    /// before decrypting or exporting. A no-op for Secure Enclave keys.
    public func withKeychainSecret(_ secret: String) -> AgeIdentity {
        with(material: material.withKeychain(secret: secret, protection: material.storage.keychainProtection ?? .local))
    }

    /// A copy of this keychain identity re-protected under a new `KeychainProtection`,
    /// carrying the given secret. Used when moving a key between local / synced /
    /// authenticated storage. A no-op for Secure Enclave keys.
    public func withKeychainProtection(_ protection: KeychainProtection, secretKey: String) -> AgeIdentity {
        with(material: material.withKeychain(secret: secretKey, protection: protection))
    }

    private func with(material: IdentityMaterial) -> AgeIdentity {
        AgeIdentity(id: id, label: label, created: created, material: material, recipient: recipient)
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
            throw AssuageError(sshKeyError: error, context: pem)
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
        guard let data = Data(base64Encoded: seed) else { throw AssuageError.unrecognizedIdentity(seed) }
        do {
            return try Age.SSHEd25519Identity(seed: Array(data))
        } catch {
            throw AssuageError.unrecognizedIdentity(seed)
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
            throw AssuageError.unrecognizedIdentity(secretKey)
        }
        guard let x25519 = identities.first as? Age.X25519Identity else {
            throw AssuageError.unrecognizedIdentity(secretKey)
        }
        return x25519
    }

    /// The AgeKit identity used to unwrap the file key during decryption. `stored`
    /// is the secret (keychain keys) or the identity blob (enclave keys).
    func makeAgeIdentity() throws -> any Identity {
        let stored = material.stored
        switch material.kind {
        case .x25519:
            return try Self.parseX25519(stored)
        case .sshEd25519:
            return try Self.parseSSHEd25519(seed: stored)
        case .secureEnclaveP256:
            return SecureEnclaveIdentity(privateKey: try SecureEnclaveKeys.loadPrivateKey(ageIdentity: stored))
        case .postQuantum:
            guard #available(macOS 26, iOS 26, *) else { throw Self.postQuantumUnavailable }
            return try Self.parsePostQuantum(stored)
        case .secureEnclavePostQuantum:
            guard #available(macOS 26, iOS 26, *) else { throw Self.postQuantumUnavailable }
            return try SecureEnclavePostQuantumKeys.loadIdentity(stored)
        }
    }

    private static var postQuantumUnavailable: AssuageError {
        .featureNotYetImplemented("Post-quantum keys require macOS 26 or later.")
    }

    /// Rebuild the AgeKit post-quantum identity from a stored `AGE-SECRET-KEY-PQ-…`
    /// secret string.
    @available(macOS 26, iOS 26, *)
    static func parsePostQuantum(_ secretKey: String) throws -> Age.MLKEM768X25519Identity {
        do {
            return try Age.MLKEM768X25519Identity(secretKey.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw AssuageError.unrecognizedIdentity(secretKey)
        }
    }

    /// Generate a fresh post-quantum (MLKEM768-X25519 / X-Wing) identity, stored in
    /// the keychain. Secure against a future quantum computer.
    ///
    /// - Parameter protection: where the secret is stored and how it's guarded.
    @available(macOS 26, iOS 26, *)
    public static func generatePostQuantum(label: String = "", protection: KeychainProtection = .local, created: Date = Date()) throws -> AgeIdentity {
        let identity = try Age.MLKEM768X25519Identity.generate()
        return AgeIdentity(
            id: UUID(),
            label: label,
            created: created,
            material: .postQuantum(secretKey: identity.string, protection: protection),
            recipient: AgeRecipient(kind: .postQuantum, encoding: identity.recipient.string)
        )
    }

    /// Generate a new Secure Enclave identity on this Mac.
    ///
    /// - Throws: `AssuageError.secureEnclaveUnavailable` on Macs without a Secure Enclave.
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

    /// Generate a new hardware post-quantum identity on this Mac — an ML-KEM-768 and
    /// a P-256 key both bound to the Secure Enclave (`age1tagpq…`). Requires macOS 26.
    @available(macOS 26, iOS 26, *)
    public static func generateSecureEnclavePostQuantum(
        label: String = "",
        accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode,
        created: Date = Date()
    ) throws -> AgeIdentity {
        let generated = try SecureEnclavePostQuantumKeys.generate(accessControl: accessControl)
        return AgeIdentity(
            id: UUID(),
            label: label,
            created: created,
            material: .secureEnclavePostQuantum(identity: generated.identity, accessControl: accessControl),
            recipient: AgeRecipient(kind: .postQuantumHardware, encoding: generated.recipient)
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
        if let accessControl = material.storage.accessControl {
            lines.append("# access control: \(accessControl.ageLabel)")
        }
        lines.append("# public key: \(recipient.encoding)")
        // SSH exports as a real OpenSSH private key (which age/rage accept via -i),
        // reconstructed from the stored seed; every other kind writes its stored string.
        if material.kind == .sshEd25519, let identity = try? Self.parseSSHEd25519(seed: material.stored) {
            lines.append(identity.opensshPEM())
        } else {
            lines.append(material.stored)
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
