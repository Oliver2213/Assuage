import Foundation
import CryptoKit
import AgeKit

// AgeKit's `Age.encrypt`/`Age.decrypt` take *variadic* recipients/identities,
// which can't be fed a dynamically-sized array. Rather than fork AgeKit, we lean
// on how it uses them:
//
//   • `encrypt` calls `wrap(fileKey:)` on each recipient and concatenates the
//     returned stanzas — so one recipient that returns *everyone's* stanzas
//     produces a byte-identical header.
//   • `decrypt` calls `unwrap(stanzas:)` on each identity and takes the first
//     that succeeds — so one identity that tries each in turn behaves the same.
//
// This keeps arbitrary-N recipients/identities working while calling AgeKit with
// a single value.

/// A recipient that fans a file key out to several underlying recipients.
struct CompositeRecipient: Recipient {
    let recipients: [any Recipient]

    func wrap(fileKey: SymmetricKey) throws -> [Age.Stanza] {
        try recipients.flatMap { try $0.wrap(fileKey: fileKey) }
    }
}

/// An identity that tries several underlying identities until one unwraps the key.
struct CompositeIdentity: Identity {
    let identities: [any Identity]

    func unwrap(stanzas: [Age.Stanza]) throws -> SymmetricKey {
        for identity in identities {
            do {
                return try identity.unwrap(stanzas: stanzas)
            } catch Age.DecryptError.incorrectIdentity {
                continue
            }
        }
        throw Age.DecryptError.incorrectIdentity
    }
}

extension Array where Element == AgeRecipient {
    /// Collapse to a single AgeKit recipient suitable for `Age.encrypt`.
    func makeAgeRecipient() throws -> any Recipient {
        guard !isEmpty else { throw CypherdexError.noRecipients }
        let wrapped = try map { try $0.makeAgeRecipient() }
        return wrapped.count == 1 ? wrapped[0] : CompositeRecipient(recipients: wrapped)
    }
}

extension Array where Element == AgeIdentity {
    /// Collapse to a single AgeKit identity suitable for `Age.decrypt`.
    func makeAgeIdentity() throws -> any Identity {
        guard !isEmpty else { throw CypherdexError.noIdentities }
        let wrapped = try map { try $0.makeAgeIdentity() }
        return wrapped.count == 1 ? wrapped[0] : CompositeIdentity(identities: wrapped)
    }
}
