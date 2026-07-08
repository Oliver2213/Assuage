import Foundation
import CryptoKit
import AgeKit

/// Whether a set of identities can decrypt an age file, judged from the header
/// alone — no secret keys are read and the Secure Enclave is never touched. Safe
/// to run on untrusted files and cheap enough for a Finder preview, a Shortcut,
/// or an App Intent.
///
/// It works because the non-anonymous recipient types (`ssh-ed25519`, `piv-p256`,
/// `p256tag`) carry a short tag derived from the recipient's *public* key. X25519
/// recipients are anonymous — they carry no such tag — so a file addressed only
/// to X25519 keys can't be judged without trying a secret.
public enum DecryptionCapability: Sendable, Equatable {
    /// One or more held identities are provably addressed by the file — their
    /// public-key tag appears in the header. Decryptable without a passphrase.
    case decryptable(matching: [AgeIdentity])
    /// The file is locked by a passphrase (`scrypt`); no key applies.
    case passphraseRequired
    /// Can't be told from the header alone: the file has anonymous X25519
    /// recipients and at least one held X25519 key *might* unwrap it — only
    /// attempting a decrypt will confirm.
    case undetermined
    /// Recipients are present, but none is addressed to a held key and none is an
    /// anonymous type a held key could match. This file isn't decryptable by you.
    case noMatchingKey

    /// Whether a held key definitely or possibly works (`.decryptable` /
    /// `.undetermined`).
    public var isPlausible: Bool {
        switch self {
        case .decryptable, .undetermined: return true
        case .passphraseRequired, .noMatchingKey: return false
        }
    }

    /// The identities proven to address the file, or `[]` when none is proven.
    public var matchingIdentities: [AgeIdentity] {
        if case .decryptable(let ids) = self { return ids }
        return []
    }
}

extension AgeFileInfo {
    /// Judge whether `identities` can decrypt this file, from the header only.
    /// Reads no secrets and never prompts.
    public func decryptability(with identities: [AgeIdentity]) -> DecryptionCapability {
        if isPassphrase { return .passphraseRequired }

        let matching = identities.filter { addresses($0) }
        if !matching.isEmpty { return .decryptable(matching: matching) }

        // No provable match. An anonymous X25519 recipient might still be for one
        // of our X25519 keys — the header can't say which.
        let hasAnonymousX25519 = recipients.contains { $0.kind == .x25519 }
        let holdsX25519 = identities.contains { $0.recipient.kind == .x25519 }
        if hasAnonymousX25519 && holdsX25519 { return .undetermined }

        return .noMatchingKey
    }

    /// Whether any recipient stanza is provably addressed to `identity`, using
    /// only public information: the identity's public recipient plus the in-header
    /// ephemeral share. Never touches a secret or the Secure Enclave.
    private func addresses(_ identity: AgeIdentity) -> Bool {
        switch identity.recipient.kind {
        case .sshEd25519:
            guard let recipient = try? Age.SSHEd25519Recipient(authorizedKey: identity.recipient.encoding) else {
                return false
            }
            let fingerprint = recipient.fingerprint
            return recipients.contains { $0.kind == .sshEd25519 && $0.args.first == fingerprint }

        case .secureEnclave:
            // The same P256 public key can be addressed as either piv-p256 or
            // p256tag; match whichever stanza type is present.
            guard let publicKey = try? P256.KeyAgreement.PublicKey(ageSecureEnclaveRecipient: identity.recipient.encoding) else {
                return false
            }
            return recipients.contains { stanza in
                switch stanza.kind {
                case .secureEnclave:   // piv-p256: tag = SHA256(pubkey)[:4]
                    return stanza.args.first == publicKey.sha256Tag.base64RawEncodedString
                case .p256Tag:         // p256tag: tag = HMAC(pubkey, key = ephemeral share)
                    guard stanza.args.count >= 2, let share = Data(base64RawEncoded: stanza.args[1]) else {
                        return false
                    }
                    return stanza.args[0] == publicKey.hmacTag(using: SymmetricKey(data: share)).base64RawEncodedString
                default:
                    return false
                }
            }

        case .x25519:
            // Anonymous recipient type — nothing in the header to match against.
            return false
        }
    }
}

/// Header-only decryptability checks that parse the file first — the entry points
/// a Finder preview, Shortcut, or App Intent calls. Deliberately free of any UI
/// or `@MainActor` coupling so the capability isn't bound to the app's views.
public enum DecryptionCapabilityChecker {
    /// Judge whether `identities` can decrypt the age file `data`, header only.
    ///
    /// - Throws: `CypherdexError.invalidAgeFile` if `data` isn't a parseable age file.
    public static func capability(of data: Data, for identities: [AgeIdentity]) throws -> DecryptionCapability {
        try AgeFileInspector.inspect(data).decryptability(with: identities)
    }

    /// Judge whether `identities` can decrypt the age file at `url`, reading only
    /// its header (the file is memory-mapped, so large files aren't copied).
    ///
    /// - Throws: `CypherdexError.invalidAgeFile` if the file isn't a parseable age file.
    public static func capability(ofFileAt url: URL, for identities: [AgeIdentity]) throws -> DecryptionCapability {
        try AgeFileInspector.inspect(contentsOf: url).decryptability(with: identities)
    }
}
