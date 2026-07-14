import Foundation
import CryptoKit

/// The public half of a note signer — an Ed25519 public key bound to a name — in
/// the C2SP signed-note encoding (`c2sp.org/signed-note`, the format Go's
/// `sumdb/note` implements). This is what you hand out so others can verify your
/// notes, and what the app stores for signers it trusts.
///
/// The name is bound *into* the key: the 4-byte key ID is a hash over the name and
/// the public key together, so the same key material under a different name is a
/// different verifier key. See `SigningIdentity` for the private half.
public struct VerifierKey: Sendable, Hashable, Codable, Identifiable {
    /// The signer's name. Non-empty, valid UTF-8, no Unicode spaces, no `+`.
    public let name: String
    /// The raw 32-byte Ed25519 public key.
    public let publicKey: Data

    /// The stable encoded form doubles as the identity.
    public var id: String { encoded }

    /// The Ed25519 algorithm identifier byte, per the spec.
    static let algorithmEd25519: UInt8 = 0x01

    /// Build a verifier key from a name and a raw 32-byte Ed25519 public key.
    ///
    /// - Throws: `AssuageError.invalidSignerName` if the name breaks the spec's
    ///   rules, or `AssuageError.unrecognizedIdentity` if the key isn't 32 bytes.
    public init(name: String, publicKey: Data) throws {
        try Self.validate(name: name)
        guard publicKey.count == 32 else { throw AssuageError.unrecognizedIdentity(name) }
        self.name = name
        self.publicKey = publicKey
    }

    /// Parse a verifier key in its encoded `name+hexKeyID+base64(alg‖key)` form.
    ///
    /// The base64 field can itself contain `+`, so we split on only the first two
    /// separators (name and hex ID contain none) and keep the remainder as the key.
    ///
    /// - Throws: `AssuageError.unrecognizedIdentity` if the shape, algorithm byte,
    ///   key ID, or key length is wrong.
    public init(parsing encoded: String) throws {
        let (name, hexID, keyData) = try Self.split(encoded, privatePrefix: false)
        guard keyData.count == 33, keyData.first == Self.algorithmEd25519 else {
            throw AssuageError.unrecognizedIdentity(encoded)
        }
        try self.init(name: name, publicKey: keyData.dropFirst())
        // The embedded key ID must match the one we compute, or the encoding is
        // corrupt or refers to a different key than it claims.
        guard hexID == keyIDHex else { throw AssuageError.unrecognizedIdentity(encoded) }
    }

    /// The 4-byte key ID: the first four bytes of `SHA-256(name ‖ 0x0A ‖ 0x01 ‖ key)`.
    /// These same four bytes prefix every signature, so a verifier can pick which
    /// key to check without trial-verifying against all of them.
    public var keyIDBytes: [UInt8] {
        Self.keyIDBytes(name: name, algorithmAndKey: [Self.algorithmEd25519] + publicKey)
    }

    /// The key ID as eight lowercase hex digits, as it appears in the encoding.
    public var keyIDHex: String { keyIDBytes.map { String(format: "%02x", $0) }.joined() }

    /// The encoded verifier key: `name+hexKeyID+base64(0x01 ‖ publicKey)`.
    public var encoded: String {
        let payload = Data([Self.algorithmEd25519] + publicKey).base64EncodedString()
        return "\(name)+\(keyIDHex)+\(payload)"
    }

    /// Whether `signature` (the raw 64-byte Ed25519 signature, without the key-ID
    /// prefix) is valid for `message` under this key.
    public func isValidSignature(_ signature: Data, for message: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    // MARK: - Shared helpers

    /// The spec's key ID: `SHA-256(name ‖ 0x0A ‖ algorithmByte ‖ publicKey)[0..<4]`.
    static func keyIDBytes(name: String, algorithmAndKey: [UInt8]) -> [UInt8] {
        var input = Data(name.utf8)
        input.append(0x0A) // newline
        input.append(contentsOf: algorithmAndKey)
        return Array(SHA256.hash(data: input).prefix(4))
    }

    /// Whether `name` is a valid signer name — for live UI validation. See `validate`.
    public static func isValidName(_ name: String) -> Bool {
        (try? validate(name: name)) != nil
    }

    /// Validate a signer name against the spec: non-empty, no Unicode whitespace,
    /// no `+` (the field separator).
    static func validate(name: String) throws {
        guard !name.isEmpty,
              !name.contains("+"),
              !name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw AssuageError.invalidSignerName(name) }
    }

    /// Split a `name+hex+base64` string (optionally after the `PRIVATE+KEY+` prefix)
    /// into its three fields, keeping any `+` inside the trailing base64 field.
    static func split(_ encoded: String, privatePrefix: Bool) throws -> (name: String, hexID: String, payload: Data) {
        var body = Substring(encoded)
        if privatePrefix {
            let prefix = "PRIVATE+KEY+"
            guard body.hasPrefix(prefix) else { throw AssuageError.unrecognizedIdentity(encoded) }
            body = body.dropFirst(prefix.count)
        }
        guard let firstPlus = body.firstIndex(of: "+") else { throw AssuageError.unrecognizedIdentity(encoded) }
        let name = String(body[..<firstPlus])
        let afterName = body[body.index(after: firstPlus)...]
        guard let secondPlus = afterName.firstIndex(of: "+") else { throw AssuageError.unrecognizedIdentity(encoded) }
        let hexID = String(afterName[..<secondPlus])
        let payloadString = String(afterName[afterName.index(after: secondPlus)...])
        guard hexID.count == 8, let payload = Data(base64Encoded: payloadString) else {
            throw AssuageError.unrecognizedIdentity(encoded)
        }
        return (name, hexID, payload)
    }
}
