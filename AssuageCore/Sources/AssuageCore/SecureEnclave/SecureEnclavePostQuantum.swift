import Foundation
import CryptoKit
import LocalAuthentication
import AgeKit

// Hardware post-quantum keys: an ML-KEM-768 key and a P-256 key, both bound to the
// Secure Enclave, together forming a `mlkem768p256tag` (`age1tagpq…`) recipient.
// Encryption uses AgeKit's `MLKEM768P256Recipient`; decryption decapsulates inside
// the enclave via `MLKEM768P256Identity`. Both the recipient/stanza AND the identity
// encoding are wire-compatible with age-plugin-se, so a key generated in either
// tool imports into the other (on the same Mac — the enclave blobs are device-bound).
//
// Requires macOS 26 for CryptoKit's Secure Enclave ML-KEM.

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, *)
enum SecureEnclavePostQuantumKeys {
    /// Bech32 HRP, shared with classical Secure Enclave identities: age-plugin-se
    /// uses one HRP for both and tells them apart by parsing (see `parseContainer`).
    static let identityHRP = "AGE-PLUGIN-SE-"

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

    /// Whether an `AGE-PLUGIN-SE-` identity is a post-quantum one (its payload is the
    /// two-blob container) rather than a classical P-256 identity. Enclave-free, so
    /// it can route an imported identity without prompting.
    static func isPostQuantum(_ ageIdentity: String) -> Bool {
        guard let decoded = try? Bech32().decode(ageIdentity), decoded.hrp == identityHRP else { return false }
        return parseContainer(decoded.data) != nil
    }

    // MARK: Encoding

    /// The age-plugin-se post-quantum container:
    /// `I2OSP(len(p256), 2) ‖ p256 blob ‖ I2OSP(len(mlkem), 2) ‖ mlkem blob`.
    private static func encodeIdentity(mlkemBlob: Data, p256Blob: Data) -> String {
        var data = Data()
        data.appendLengthPrefixed(p256Blob)
        data.appendLengthPrefixed(mlkemBlob)
        return Bech32().encode(hrp: identityHRP, data: data)
    }

    /// Split an `AGE-PLUGIN-SE-` payload into its P-256 and ML-KEM blobs, or `nil`
    /// if it isn't a post-quantum container — mirroring age-plugin-se, which requires
    /// two length-prefixed blobs that consume the payload exactly (a classical
    /// identity's payload is the P-256 blob alone and won't parse this way).
    static func parseContainer(_ data: Data) -> (p256: Data, mlkem: Data)? {
        let bytes = [UInt8](data)
        var offset = 0
        func readBlob() -> Data? {
            guard offset + 2 <= bytes.count else { return nil }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard offset + length <= bytes.count else { return nil }
            defer { offset += length }
            return Data(bytes[offset..<offset + length])
        }
        guard let p256 = readBlob(), let mlkem = readBlob(), offset == bytes.count else { return nil }
        return (p256, mlkem)
    }

    private static func reconstruct(_ ageIdentity: String) throws
        -> (mlkem: SecureEnclave.MLKEM768.PrivateKey, p256: SecureEnclave.P256.KeyAgreement.PrivateKey) {
        guard let decoded = try? Bech32().decode(ageIdentity), decoded.hrp == identityHRP,
              let blobs = parseContainer(decoded.data) else {
            throw AssuageError.unrecognizedIdentity(ageIdentity)
        }
        let context = LAContext()
        do {
            let mlkem = try SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: blobs.mlkem, authenticationContext: context)
            let p256 = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blobs.p256, authenticationContext: context)
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

private extension Data {
    /// Append `I2OSP(blob.count, 2) ‖ blob` (a big-endian 16-bit length prefix).
    mutating func appendLengthPrefixed(_ blob: Data) {
        append(UInt8(blob.count >> 8))
        append(UInt8(blob.count & 0xff))
        append(blob)
    }
}
