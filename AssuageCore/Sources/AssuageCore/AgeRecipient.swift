import Foundation
import CryptoKit
import AgeKit

/// A public recipient the app can encrypt to.
///
/// A value of this type is always well-formed: the only public initialiser
/// validates the encoding, so an `AgeRecipient` can never hold a string that
/// isn't a real recipient. The canonical age encoding is stored verbatim.
public struct AgeRecipient: Sendable, Hashable, Identifiable, Codable {
    /// The recipient scheme, inferred from the encoding's human-readable prefix.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// Native age X25519 public key: `age1…`
        case x25519
        /// Secure Enclave public key: `age1se1…` / `age1p256tag1…`.
        case secureEnclave
        /// An SSH Ed25519 public key: an `ssh-ed25519 AAAA… [comment]` line.
        case sshEd25519
    }

    public let kind: Kind

    /// The canonical recipient string. Usually a bech32 `age1…` encoding, but for
    /// an SSH recipient it's the full `authorized_keys` line (with any comment) —
    /// so this is not always an `age1…` token.
    public let encoding: String

    /// Deduplication key. For SSH recipients this is the key itself — the
    /// `ssh-ed25519 <base64>` fields without the trailing comment — mirroring how
    /// age keys dedupe by their (comment-less) public-key encoding.
    public var id: String {
        guard kind == .sshEd25519 else { return encoding }
        return encoding.split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// Parse and validate a recipient string.
    ///
    /// - Throws: `AssuageError.unrecognizedRecipient` if the string isn't a
    ///   recipient we understand.
    public init(parsing raw: String) throws {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw AssuageError.unrecognizedRecipient(raw) }

        // Order matters: the Secure Enclave prefixes are more specific than `age1`.
        if s.hasPrefix("age1se1") || s.hasPrefix("age1p256tag1") {
            _ = try P256.KeyAgreement.PublicKey(ageSecureEnclaveRecipient: s)  // validates
            self.kind = .secureEnclave
            self.encoding = s
        } else if s.hasPrefix("age1") {
            _ = try Age.X25519Recipient(s)   // validates Bech32 + key length
            self.kind = .x25519
            self.encoding = s
        } else if s.hasPrefix("ssh-ed25519") {
            do {
                _ = try Age.SSHEd25519Recipient(authorizedKey: s)   // validates the wire encoding
            } catch {
                throw AssuageError.unrecognizedRecipient(raw)
            }
            self.kind = .sshEd25519
            self.encoding = s
        } else if s.hasPrefix("ssh-rsa") || s.hasPrefix("ecdsa-") || s.hasPrefix("sk-") {
            // Recognizable SSH keys we don't support — give a specific message.
            throw AssuageError.unsupportedSSHKeyType(String(s.prefix(while: { $0 != " " })))
        } else {
            throw AssuageError.unrecognizedRecipient(raw)
        }
    }

    /// Construct from a value already known to be valid (e.g. derived from an identity).
    init(kind: Kind, encoding: String) {
        self.kind = kind
        self.encoding = encoding
    }

    /// The AgeKit recipient used to wrap the file key during encryption.
    func makeAgeRecipient() throws -> any Recipient {
        switch kind {
        case .x25519:
            return try Age.X25519Recipient(encoding)
        case .secureEnclave:
            let publicKey = try P256.KeyAgreement.PublicKey(ageSecureEnclaveRecipient: encoding)
            let stanzaType: SEStanzaType = encoding.hasPrefix("age1p256tag1") ? .p256tag : .pivp256
            return SecureEnclaveRecipient(publicKey: publicKey, stanzaType: stanzaType)
        case .sshEd25519:
            return try Age.SSHEd25519Recipient(authorizedKey: encoding)
        }
    }
}
