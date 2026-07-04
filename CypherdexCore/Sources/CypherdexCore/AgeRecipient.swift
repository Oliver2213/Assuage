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
    }

    public let kind: Kind

    /// The canonical age recipient string, e.g. `age1qz…`.
    public let encoding: String

    public var id: String { encoding }

    /// Parse and validate a recipient string.
    ///
    /// - Throws: `CypherdexError.unrecognizedRecipient` if the string isn't a
    ///   recipient we understand.
    public init(parsing raw: String) throws {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw CypherdexError.unrecognizedRecipient(raw) }

        // Order matters: the Secure Enclave prefixes are more specific than `age1`.
        if s.hasPrefix("age1se1") || s.hasPrefix("age1p256tag1") {
            _ = try P256.KeyAgreement.PublicKey(ageSecureEnclaveRecipient: s)  // validates
            self.kind = .secureEnclave
            self.encoding = s
        } else if s.hasPrefix("age1") {
            _ = try Age.X25519Recipient(s)   // validates Bech32 + key length
            self.kind = .x25519
            self.encoding = s
        } else {
            throw CypherdexError.unrecognizedRecipient(raw)
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
        }
    }
}
