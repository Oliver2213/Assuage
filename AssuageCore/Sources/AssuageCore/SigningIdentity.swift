import Foundation
import CryptoKit

/// The private half of a note signer: an Ed25519 keypair bound to a name, used to
/// sign text in the C2SP signed-note format (`c2sp.org/signed-note`). Unlike an
/// `AgeIdentity`, a signing identity has no age recipient — it only signs and
/// verifies; it never encrypts or decrypts.
///
/// The app stores only the 32-byte `seed` (in the keychain, like an SSH key) and
/// rebuilds the identity on demand; the name lives alongside it as metadata.
public struct SigningIdentity: Sendable {
    /// The signer's name, bound into the key ID. Non-empty, no spaces, no `+`.
    public let name: String
    private let privateKey: Curve25519.Signing.PrivateKey

    /// Build a signing identity from a name and a stored 32-byte Ed25519 seed.
    ///
    /// - Throws: `AssuageError.invalidSignerName` for a bad name, or
    ///   `.unrecognizedIdentity` if the seed isn't a valid 32-byte key.
    public init(name: String, seed: Data) throws {
        try VerifierKey.validate(name: name)
        do {
            self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            throw AssuageError.unrecognizedIdentity(name)
        }
        self.name = name
    }

    /// Generate a fresh signing identity under `name`.
    public static func generate(name: String) throws -> SigningIdentity {
        try VerifierKey.validate(name: name)
        return try SigningIdentity(name: name, key: Curve25519.Signing.PrivateKey())
    }

    private init(name: String, key: Curve25519.Signing.PrivateKey) throws {
        self.name = name
        self.privateKey = key
    }

    /// The 32-byte Ed25519 seed — what the keychain persists. Secret.
    public var seed: Data { privateKey.rawRepresentation }

    /// The public verifier key others use to check this identity's signatures.
    public var verifierKey: VerifierKey {
        // Force-try is safe: the name was validated at init and the public key is
        // always 32 bytes from CryptoKit.
        try! VerifierKey(name: name, publicKey: privateKey.publicKey.rawRepresentation)
    }

    /// The encoded signer (private) key: `PRIVATE+KEY+name+hexKeyID+base64(0x01 ‖ seed)`.
    /// The key ID is the *public* key's, matching the verifier key — so a signer and
    /// its verifier key always share the same ID. Secret; export with care.
    public var encodedSignerKey: String {
        let payload = Data([VerifierKey.algorithmEd25519] + seed).base64EncodedString()
        return "PRIVATE+KEY+\(name)+\(verifierKey.keyIDHex)+\(payload)"
    }

    /// Parse an encoded signer key (`PRIVATE+KEY+…`) back into a signing identity.
    ///
    /// - Throws: `AssuageError.unrecognizedIdentity` if the shape, algorithm byte,
    ///   or seed length is wrong.
    public init(parsingSignerKey encoded: String) throws {
        let (name, _, payload) = try VerifierKey.split(encoded, privatePrefix: true)
        guard payload.count == 33, payload.first == VerifierKey.algorithmEd25519 else {
            throw AssuageError.unrecognizedIdentity(encoded)
        }
        try self.init(name: name, seed: payload.dropFirst())
    }

    /// Sign `message` (the note text bytes) and return the raw signature stored in a
    /// note line: the 4-byte key ID followed by the 64-byte Ed25519 signature.
    public func signatureBytes(for message: Data) throws -> Data {
        let signature = try privateKey.signature(for: message)
        return Data(verifierKey.keyIDBytes) + signature
    }
}
