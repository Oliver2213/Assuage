import Foundation
import AgeKit

/// The secret material behind an importable key, before it's committed to the store.
public enum ImportableSecret: Sendable, Hashable {
    /// A native age X25519 secret (`AGE-SECRET-KEY-1…`).
    case x25519(secretKey: String)
    /// A native age post-quantum X-Wing secret (`AGE-SECRET-KEY-PQ-1…`).
    case postQuantum(secretKey: String)
    /// An SSH Ed25519 key, reduced to its base64 32-byte seed.
    case sshEd25519(seed: String)
    /// A Secure Enclave key (`AGE-PLUGIN-SE-1…`). The blob is device-bound, so it
    /// only imports on the Mac that created it; `accessControl` is metadata read
    /// from the file's `# access control:` comment (the enclave enforces the real
    /// policy regardless).
    case secureEnclave(identity: String, accessControl: SecureEnclaveAccessControl)
    /// A hardware post-quantum Secure Enclave key (an `AGE-PLUGIN-SE-1…` whose
    /// payload is the ML-KEM-768 + P-256 container). Device-bound, like `secureEnclave`.
    case secureEnclavePostQuantum(identity: String, accessControl: SecureEnclaveAccessControl)
}

/// A single secret key found in an imported file or clipboard, validated and
/// paired with its derived public recipient — but not yet imported. The UI turns
/// each of these into an editable row (name, storage) before committing.
public struct ImportableKey: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let secret: ImportableSecret
    /// The public recipient derived from the secret, for display and dedup.
    public let recipient: AgeRecipient

    public init(id: UUID = UUID(), secret: ImportableSecret, recipient: AgeRecipient) {
        self.id = id
        self.secret = secret
        self.recipient = recipient
    }
}

extension AgeIdentity {
    /// Parse every importable key out of identity-file (or clipboard) text:
    /// every `AGE-SECRET-KEY-1…` line, every `AGE-PLUGIN-SE-1…` Secure Enclave
    /// line (only those belonging to this Mac), plus any *unencrypted* OpenSSH
    /// Ed25519 private key block. Passphrase-protected SSH keys are skipped here —
    /// import those with `importableSSHKey(fromOpenSSH:passphrase:)` once the
    /// passphrase is known. Junk and unsupported key types are ignored.
    public static func importableKeys(from text: String) -> [ImportableKey] {
        var keys: [ImportableKey] = []
        // age-plugin-se files precede the key line with `# access control: …`;
        // remember it for the SE line that follows.
        var pendingAccessControl: SecureEnclaveAccessControl?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                if let label = accessControlLabel(inComment: trimmed) {
                    pendingAccessControl = SecureEnclaveAccessControl(ageLabel: label)
                }
                continue
            }
            if trimmed.hasPrefix("AGE-SECRET-KEY-PQ-") {
                // Software X-Wing secret. Only importable on macOS 26+ (the CryptoKit
                // KEM); deriving the recipient also validates the key.
                if #available(macOS 26, iOS 26, *), let parsed = try? parsePostQuantum(trimmed) {
                    keys.append(ImportableKey(
                        secret: .postQuantum(secretKey: trimmed),
                        recipient: AgeRecipient(kind: .postQuantum, encoding: parsed.recipient.string)
                    ))
                }
            } else if trimmed.hasPrefix("AGE-SECRET-KEY-1"), let parsed = try? parseX25519(trimmed) {
                keys.append(ImportableKey(
                    secret: .x25519(secretKey: parsed.string),
                    recipient: AgeRecipient(kind: .x25519, encoding: parsed.recipient.string)
                ))
            } else if trimmed.hasPrefix("AGE-PLUGIN-SE-1") {
                // One HRP covers both classical (P-256) and post-quantum enclave keys;
                // the payload's shape decides which. Deriving the recipient also proves
                // the key belongs to this Mac. No enclave access, so no prompt.
                let accessControl = pendingAccessControl ?? .anyBiometryOrPasscode
                if #available(macOS 26, iOS 26, *), SecureEnclavePostQuantumKeys.isPostQuantum(trimmed),
                   let recipient = try? SecureEnclavePostQuantumKeys.recipient(forIdentity: trimmed) {
                    keys.append(ImportableKey(
                        secret: .secureEnclavePostQuantum(identity: trimmed, accessControl: accessControl),
                        recipient: AgeRecipient(kind: .postQuantumHardware, encoding: recipient)
                    ))
                } else if let recipient = try? SecureEnclaveKeys.recipient(forIdentity: trimmed) {
                    keys.append(ImportableKey(
                        secret: .secureEnclave(identity: trimmed, accessControl: accessControl),
                        recipient: AgeRecipient(kind: .secureEnclave, encoding: recipient)
                    ))
                }
            }
            pendingAccessControl = nil
        }
        for pem in openSSHPrivateKeyBlocks(in: text) {
            if let key = try? importableSSHKey(fromOpenSSH: pem, passphrase: nil) {
                keys.append(key)
            }
        }
        return keys
    }

    /// The value of a `# access control: …` comment, or `nil` if this isn't one.
    private static func accessControlLabel(inComment comment: String) -> String? {
        guard let range = comment.range(of: "access control:") else { return nil }
        return String(comment[range.upperBound...])
    }

    /// Build an importable key from one OpenSSH private key block. Pass
    /// `passphrase` for encrypted keys.
    ///
    /// - Throws: `AssuageError.sshPassphraseRequired` / `.incorrectPassphrase`
    ///   / `.unsupportedSSHKeyType`.
    public static func importableSSHKey(fromOpenSSH pem: String, passphrase: String?) throws -> ImportableKey {
        let identity: Age.SSHEd25519Identity
        do {
            identity = try Age.SSHEd25519Identity(opensshPEM: pem, passphrase: passphrase)
        } catch let error as SSHKeyError {
            throw AssuageError(sshKeyError: error, context: pem)
        }
        return ImportableKey(
            secret: .sshEd25519(seed: Data(identity.seed).base64EncodedString()),
            recipient: AgeRecipient(kind: .sshEd25519, encoding: identity.authorizedKey)
        )
    }

    /// Import every OpenSSH private key block in `text` using one `passphrase`
    /// (for the encrypted-key path, after the scan came up empty).
    public static func importableSSHKeys(from text: String, passphrase: String) throws -> [ImportableKey] {
        try openSSHPrivateKeyBlocks(in: text).map {
            try importableSSHKey(fromOpenSSH: $0, passphrase: passphrase)
        }
    }

    /// Whether `text` contains at least one OpenSSH private key block — used by the
    /// UI to offer a passphrase field when a scan found the block but no importable
    /// keys (i.e. it's encrypted).
    public static func containsOpenSSHPrivateKey(_ text: String) -> Bool {
        !openSSHPrivateKeyBlocks(in: text).isEmpty
    }

    /// Extract each `-----BEGIN OPENSSH PRIVATE KEY-----…-----END…-----` block.
    static func openSSHPrivateKeyBlocks(in text: String) -> [String] {
        let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let end = "-----END OPENSSH PRIVATE KEY-----"
        var blocks: [String] = []
        var rest = Substring(text)
        while let b = rest.range(of: begin), let e = rest.range(of: end, range: b.upperBound..<rest.endIndex) {
            blocks.append(String(rest[b.lowerBound..<e.upperBound]))
            rest = rest[e.upperBound...]
        }
        return blocks
    }

    /// Commit an `ImportableKey` to an identity under the given label and storage.
    public init(importing key: ImportableKey, label: String, created: Date = Date(), protection: KeychainProtection) throws {
        switch key.secret {
        case .x25519(let secretKey):
            try self.init(importingX25519: secretKey, label: label, created: created, protection: protection)
        case .postQuantum(let secretKey):
            // Already validated (it produced `key.recipient`), so build directly.
            self.init(
                id: UUID(),
                label: label,
                created: created,
                material: .postQuantum(secretKey: secretKey, protection: protection),
                recipient: key.recipient
            )
        case .sshEd25519(let seed):
            // The seed is already validated (it produced `key.recipient`), so build directly.
            self.init(
                id: UUID(),
                label: label,
                created: created,
                material: .sshEd25519(seed: seed, protection: protection),
                recipient: key.recipient
            )
        case .secureEnclave(let identity, let accessControl):
            // Device-bound: `protection` doesn't apply. The recipient was already
            // derived by reconstructing the enclave key on this Mac.
            self.init(
                id: UUID(),
                label: label,
                created: created,
                material: .secureEnclave(identity: identity, accessControl: accessControl),
                recipient: key.recipient
            )
        case .secureEnclavePostQuantum(let identity, let accessControl):
            self.init(
                id: UUID(),
                label: label,
                created: created,
                material: .secureEnclavePostQuantum(identity: identity, accessControl: accessControl),
                recipient: key.recipient
            )
        }
    }
}
