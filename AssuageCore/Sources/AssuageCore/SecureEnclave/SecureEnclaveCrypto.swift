import Foundation
import CryptoKit
import LocalAuthentication
import AgeKit

// Native re-implementation of age-plugin-se's recipient/identity crypto, so
// Secure Enclave keys encrypt and decrypt fully in-process and produce age files
// that are wire-compatible with the reference plugin. Reference:
// ~/src/age-plugin-se/Sources/Plugin.swift (recipientStanzaWrapKey, runRecipientV1,
// runIdentityV1) and Crypto.swift.

/// The stanza type written into the age file header for a Secure Enclave recipient.
enum SEStanzaType: String {
    /// Default SE recipients (`age1se1…`).
    case pivp256 = "piv-p256"
    /// yubikey-compatible recipients (`age1p256tag1…`).
    case p256tag = "p256tag"
}

/// Derive the ChaChaPoly key wrapping the file key, matching age-plugin-se.
func secureEnclaveWrapKey(sharedSecret: SharedSecret, salt: Data, type: SEStanzaType) -> SymmetricKey {
    switch type {
    case .p256tag:
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("age-encryption.org/v1/p256tag".utf8),
            sharedInfo: salt,
            outputByteCount: 32
        )
    case .pivp256:
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("piv-p256".utf8),
            outputByteCount: 32
        )
    }
}

extension P256.KeyAgreement.PublicKey {
    /// First 4 bytes of SHA-256(compressed public key) — the `piv-p256` recipient tag.
    var sha256Tag: Data { Data(SHA256.hash(data: compressedRepresentation).prefix(4)) }

    /// First 4 bytes of HMAC-SHA256(compressed public key) — the `p256tag` recipient tag.
    func hmacTag(using key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: compressedRepresentation, using: key).prefix(4))
    }

    /// Decode an `age1se1…` / `age1p256tag1…` recipient into a P256 public key.
    init(ageSecureEnclaveRecipient string: String) throws {
        let decoded: (hrp: String, data: Data)
        do {
            decoded = try Bech32().decode(string)
        } catch {
            throw CypherdexError.unrecognizedRecipient(string)
        }
        guard decoded.hrp == "age1se" || decoded.hrp == "age1p256tag" else {
            throw CypherdexError.unrecognizedRecipient(string)
        }
        do {
            self = try P256.KeyAgreement.PublicKey(compressedRepresentation: decoded.data)
        } catch {
            throw CypherdexError.unrecognizedRecipient(string)
        }
    }
}

/// A Secure Enclave recipient: encrypts to a P256 public key. No enclave access is
/// needed to encrypt (public-key only).
struct SecureEnclaveRecipient: Recipient {
    let publicKey: P256.KeyAgreement.PublicKey
    let stanzaType: SEStanzaType

    func wrap(fileKey: SymmetricKey) throws -> [Age.Stanza] {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeral.publicKey.compressedRepresentation
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let salt = ephemeralPublicKey + publicKey.compressedRepresentation
        let wrapKey = secureEnclaveWrapKey(sharedSecret: sharedSecret, salt: salt, type: stanzaType)

        let fileKeyData = fileKey.withUnsafeBytes { Data($0) }
        let sealed = try ChaChaPoly.seal(
            fileKeyData, using: wrapKey, nonce: ChaChaPoly.Nonce(data: Data(count: 12))
        )

        let tag: Data
        switch stanzaType {
        case .p256tag:
            tag = publicKey.hmacTag(using: SymmetricKey(data: ephemeralPublicKey))
        case .pivp256:
            tag = publicKey.sha256Tag
        }

        return [Age.Stanza(
            type: stanzaType.rawValue,
            args: [tag.base64RawEncodedString, ephemeralPublicKey.base64RawEncodedString],
            body: sealed.ciphertext + sealed.tag
        )]
    }
}

/// A Secure Enclave identity: unwraps the file key using an enclave-bound private
/// key. Using the key performs ECDH inside the Secure Enclave, which triggers the
/// key's presence policy (Touch ID / passcode).
struct SecureEnclaveIdentity: Identity {
    let privateKey: SecureEnclave.P256.KeyAgreement.PrivateKey

    func unwrap(stanzas: [Age.Stanza]) throws -> SymmetricKey {
        let myPublicKey = privateKey.publicKey
        for stanza in stanzas {
            guard let type = SEStanzaType(rawValue: stanza.type), stanza.args.count == 2 else {
                continue
            }
            guard let share = Data(base64RawEncoded: stanza.args[1]), share.count == 33,
                  let tag = Data(base64RawEncoded: stanza.args[0]), tag.count == 4 else {
                continue
            }

            // Cheap public-key tag check: skip stanzas not addressed to this key
            // before touching the enclave (and prompting the user).
            let expectedTag: Data
            switch type {
            case .p256tag: expectedTag = myPublicKey.hmacTag(using: SymmetricKey(data: share))
            case .pivp256: expectedTag = myPublicKey.sha256Tag
            }
            guard tag == expectedTag else { continue }

            guard let shareKey = try? P256.KeyAgreement.PublicKey(compressedRepresentation: share) else {
                continue
            }
            do {
                let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: shareKey)
                let salt = share + myPublicKey.compressedRepresentation
                let wrapKey = secureEnclaveWrapKey(sharedSecret: sharedSecret, salt: salt, type: type)
                // Reassemble the sealed box with the all-zero 12-byte nonce used at seal time.
                let combined = Data(count: 12) + stanza.body
                let opened = try ChaChaPoly.open(
                    ChaChaPoly.SealedBox(combined: combined), using: wrapKey
                )
                return SymmetricKey(data: opened)
            } catch {
                // Wrong key or tampered stanza — keep looking.
                continue
            }
        }
        throw Age.DecryptError.incorrectIdentity
    }
}

/// Generating and loading Secure Enclave keys.
public enum SecureEnclaveKeys {
    /// Whether this Mac has a Secure Enclave.
    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Generate a new Secure Enclave key. Returns the age identity string
    /// (`AGE-PLUGIN-SE-1…`) and the recipient string (`age1se1…`).
    static func generate(accessControl: SecureEnclaveAccessControl) throws -> (identity: String, recipient: String) {
        guard SecureEnclave.isAvailable else { throw CypherdexError.secureEnclaveUnavailable }
        let secAccessControl = try accessControl.makeSecAccessControl()
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            accessControl: secAccessControl, authenticationContext: LAContext()
        )
        let identity = Bech32().encode(hrp: "AGE-PLUGIN-SE-", data: key.dataRepresentation)
        let recipient = Bech32().encode(hrp: "age1se", data: key.publicKey.compressedRepresentation)
        return (identity, recipient)
    }

    /// The recipient (`age1se1…`) for an `AGE-PLUGIN-SE-1…` identity, derived by
    /// reconstructing the enclave key. This also proves the key belongs to *this*
    /// Mac — the private-key blob is device-bound, so a key from another machine
    /// throws `unrecognizedIdentity`. No presence prompt: only the public key is
    /// derived, never a key agreement.
    public static func recipient(forIdentity ageIdentity: String) throws -> String {
        let key = try loadPrivateKey(ageIdentity: ageIdentity)
        return Bech32().encode(hrp: "age1se", data: key.publicKey.compressedRepresentation)
    }

    /// Load the enclave private key behind an `AGE-PLUGIN-SE-1…` identity string.
    static func loadPrivateKey(ageIdentity: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let decoded: (hrp: String, data: Data)
        do {
            decoded = try Bech32().decode(ageIdentity)
        } catch {
            throw CypherdexError.unrecognizedIdentity(ageIdentity)
        }
        guard decoded.hrp == "AGE-PLUGIN-SE-" else {
            throw CypherdexError.unrecognizedIdentity(ageIdentity)
        }
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: decoded.data, authenticationContext: LAContext()
        )
    }
}
