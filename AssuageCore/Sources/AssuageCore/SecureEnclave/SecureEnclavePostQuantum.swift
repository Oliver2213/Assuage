import Foundation
import CryptoKit
import LocalAuthentication
import AgeKit

// Hardware post-quantum keys: an ML-KEM-768 key and a P-256 key, both bound to the
// Secure Enclave, together forming a `mlkem768p256tag` (`age1tagpq…`) recipient.
// Encryption uses AgeKit's `MLKEM768P256Recipient`; decryption decapsulates inside
// the enclave via `MLKEM768P256Identity`. The recipient/stanza are wire-compatible
// with age-plugin-se; the identity encoding below is our own (both enclave key
// blobs), so a key generated here decrypts here.
//
// Requires macOS 26 for CryptoKit's Secure Enclave ML-KEM.

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, *)
enum SecureEnclavePostQuantumKeys {
    /// Bech32 HRP for our two-blob identity encoding.
    static let identityHRP = "AGE-PLUGIN-SE-PQ-"

    /// Generate a new hardware post-quantum key. Returns the identity string
    /// (`AGE-PLUGIN-SE-PQ-1…`, encoding both enclave key blobs) and the recipient
    /// (`age1tagpq1…`).
    static func generate(accessControl: SecureEnclaveAccessControl) throws -> (identity: String, recipient: String) {
        guard SecureEnclave.isAvailable else { throw AssuageError.secureEnclaveUnavailable }
        let secAccessControl = try accessControl.makeSecAccessControl()
        let context = LAContext()
        let mlkem = try SecureEnclave.MLKEM768.PrivateKey(accessControl: secAccessControl, authenticationContext: context)
        let p256 = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: secAccessControl, authenticationContext: context)

        let identity = encodeIdentity(mlkemBlob: mlkem.dataRepresentation, p256Blob: p256.dataRepresentation)
        let recipient = recipientString(mlkem: mlkem.publicKey, p256: p256.publicKey)
        return (identity, recipient)
    }

    /// The `age1tagpq…` recipient for the given public keys: ML-KEM-768 encapsulation
    /// key ‖ uncompressed P-256 point.
    static func recipientString(mlkem: MLKEM768.PublicKey, p256: P256.KeyAgreement.PublicKey) -> String {
        Bech32().encode(hrp: "age1tagpq", data: mlkem.rawRepresentation + p256.publicKeyPoint)
    }

    /// The recipient for an identity string, by reconstructing the enclave keys and
    /// reading only their public parts (no key agreement, so no presence prompt).
    /// Also proves the key belongs to this Mac — the blobs are device-bound.
    static func recipient(forIdentity ageIdentity: String) throws -> String {
        let (mlkem, p256) = try reconstruct(ageIdentity)
        return recipientString(mlkem: mlkem.publicKey, p256: p256.publicKey)
    }

    /// The AgeKit identity that decapsulates this key inside the enclave (which
    /// triggers the key's presence policy). Used during decryption.
    static func loadIdentity(_ ageIdentity: String) throws -> Age.MLKEM768P256Identity {
        let (mlkem, p256) = try reconstruct(ageIdentity)
        return Age.MLKEM768P256Identity(
            p256PublicKey: p256.publicKey,
            mlkemDecapsulate: { try mlkem.decapsulate($0) },
            p256KeyAgreement: { try p256.sharedSecretFromKeyAgreement(with: $0) })
    }

    // MARK: Encoding

    /// `UInt16(big-endian, mlkem blob length) ‖ mlkem blob ‖ p256 blob`.
    private static func encodeIdentity(mlkemBlob: Data, p256Blob: Data) -> String {
        var data = Data()
        data.append(UInt8(mlkemBlob.count >> 8))
        data.append(UInt8(mlkemBlob.count & 0xff))
        data.append(mlkemBlob)
        data.append(p256Blob)
        return Bech32().encode(hrp: identityHRP, data: data)
    }

    private static func reconstruct(_ ageIdentity: String) throws
        -> (mlkem: SecureEnclave.MLKEM768.PrivateKey, p256: SecureEnclave.P256.KeyAgreement.PrivateKey) {
        let decoded: (hrp: String, data: Data)
        do {
            decoded = try Bech32().decode(ageIdentity)
        } catch {
            throw AssuageError.unrecognizedIdentity(ageIdentity)
        }
        guard decoded.hrp == identityHRP, decoded.data.count >= 2 else {
            throw AssuageError.unrecognizedIdentity(ageIdentity)
        }
        let data = decoded.data
        let mlkemLen = Int(data[data.startIndex]) << 8 | Int(data[data.startIndex + 1])
        let rest = data.dropFirst(2)
        guard rest.count > mlkemLen else { throw AssuageError.unrecognizedIdentity(ageIdentity) }
        let mlkemBlob = Data(rest.prefix(mlkemLen))
        let p256Blob = Data(rest.dropFirst(mlkemLen))
        let context = LAContext()
        do {
            let mlkem = try SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: mlkemBlob, authenticationContext: context)
            let p256 = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: p256Blob, authenticationContext: context)
            return (mlkem, p256)
        } catch {
            throw AssuageError.unrecognizedIdentity(ageIdentity)
        }
    }
}

private extension P256.KeyAgreement.PublicKey {
    /// The uncompressed (65-byte) X9.63 point encoding the tagged recipient uses.
    var publicKeyPoint: Data { x963Representation }
}
