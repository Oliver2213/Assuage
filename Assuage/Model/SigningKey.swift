import Foundation
import AssuageCore

/// A note-signing identity the user holds: an Ed25519 signer bound to a name, used
/// to sign text in the signed-note format (`c2sp.org/signed-note`). Unlike an
/// `AgeIdentity` it has no age recipient — it only signs, and its public half is a
/// verifier key, not a recipient.
///
/// This is the *persisted* form. Its metadata — the name, when it was made, how
/// it's stored, and the public verifier key for display — is always readable; the
/// 32-byte `seed` is left empty in the in-memory copy (exactly as `AgeIdentity`
/// blanks its secret) and hydrated from the keychain on demand right before signing.
///
/// The name is bound *into* the key (it's hashed into the key ID), so it is
/// immutable once generated — renaming would produce a different verifier key that
/// no longer matches signatures already made. Only its storage can be changed.
nonisolated struct SigningKey: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// The signer name — part of the key's identity, so fixed after generation.
    let name: String
    let created: Date
    /// Where the seed is stored and how it's guarded. Signing keys are always
    /// keychain-backed (CryptoKit can't seal an arbitrary Ed25519 seed in the
    /// Secure Enclave), so this is never absent.
    let protection: KeychainProtection
    /// The encoded verifier key (public) — held so the UI can show the key and its
    /// ID without hydrating the secret.
    let verifierKeyEncoding: String
    /// The base64 32-byte Ed25519 seed. Empty in the in-memory copy; filled on
    /// demand for signing or export (see `KeyLibrary.hydratedSigners`).
    var seed: String

    /// The name shown in the UI.
    var displayName: String { name }

    /// The parsed public verifier key, or `nil` if the stored encoding is somehow
    /// corrupt (it never should be — it's produced by `VerifierKey.encoded`).
    var verifierKey: VerifierKey? { try? VerifierKey(parsing: verifierKeyEncoding) }

    /// The eight-hex-digit key ID, for compact display.
    var keyIDHex: String { verifierKey?.keyIDHex ?? "" }

    var isSynced: Bool { protection.isSynced }
    var requiresPresence: Bool { protection.requiresAuthentication }

    /// A human description of where the seed lives, for display in the UI.
    var storageDescription: String {
        switch protection {
        case .synced: return "Synced across your devices (iCloud)"
        case .local: return "This device only"
        case .authenticated(let auth): return "This device · \(auth.displayName)"
        }
    }

    /// The keychain secret (the base64 seed), or `nil` when not hydrated — the same
    /// accessor shape `KeychainStore` uses for age keys.
    var keychainSecret: String? { seed.isEmpty ? nil : seed }

    /// A copy with its seed filled in, for signing or export.
    func withSeed(_ seed: String) -> SigningKey {
        var copy = self
        copy.seed = seed
        return copy
    }

    /// A copy re-protected under a new storage, carrying the given seed.
    func withProtection(_ protection: KeychainProtection, seed: String) -> SigningKey {
        SigningKey(id: id, name: name, created: created, protection: protection,
                   verifierKeyEncoding: verifierKeyEncoding, seed: seed)
    }

    /// Rebuild the crypto signer for actual signing. Requires the seed to be
    /// hydrated first.
    func signingIdentity() throws -> SigningIdentity {
        guard let data = Data(base64Encoded: seed) else { throw AssuageError.unrecognizedIdentity(name) }
        return try SigningIdentity(name: name, seed: data)
    }
}

extension SigningKey {
    /// Generate a fresh signing key under `name`, stored per `protection`.
    static func generate(name: String, protection: KeychainProtection = .local, created: Date = Date()) throws -> SigningKey {
        let identity = try SigningIdentity.generate(name: name)
        return SigningKey(
            id: UUID(),
            name: name,
            created: created,
            protection: protection,
            verifierKeyEncoding: identity.verifierKey.encoded,
            seed: identity.seed.base64EncodedString()
        )
    }
}
