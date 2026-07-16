import Foundation
import AssuageCore

/// A verifier key we trust to check signatures, tagged with where it came from — your
/// own signing keys, and/or the contacts whose cards carry it.
///
/// A note's signer *name* is self-asserted: anyone can put "Alice" on a signature. So
/// the name alone doesn't say who signed — this provenance does. When a signature
/// verifies, the honest answer to "who is this?" is the source of the matching key: a
/// key saved on Alice's contact card, or one of your own.
struct TrustedKey: Identifiable, Hashable {
    let key: VerifierKey
    /// True if this matches one of your own signing identities.
    var isOwn = false
    /// Names of the contacts whose cards carry this key. Empty when it's only your own.
    var contactNames: [String] = []

    var id: String { key.id }

    /// Whether a contact vouches for this key, so the UI can pick a contact vs. self icon.
    var isFromContact: Bool { !contactNames.isEmpty }

    /// A short attribution for the "From" column: the contact name(s), or "You" for
    /// your own key, or `nil` when there's nothing to show.
    var attribution: String? {
        if !contactNames.isEmpty { return contactNames.joined(separator: ", ") }
        if isOwn { return String(localized: "You") }
        return nil
    }

    /// Build the trust set: your own verifier keys plus every note signing key saved on
    /// a contact, de-duplicated so a key held in several places becomes one entry that
    /// gathers all of its sources.
    static func all(own: [VerifierKey], contacts: [Person]) -> [TrustedKey] {
        var result: [TrustedKey] = []
        var index: [VerifierKey: Int] = [:]

        func upsert(_ key: VerifierKey, _ mutate: (inout TrustedKey) -> Void) {
            if let i = index[key] {
                mutate(&result[i])
            } else {
                var trusted = TrustedKey(key: key)
                mutate(&trusted)
                index[key] = result.count
                result.append(trusted)
            }
        }

        for key in own {
            upsert(key) { $0.isOwn = true }
        }
        for person in contacts {
            let name = person.name.isEmpty ? String(localized: "Unnamed contact") : person.name
            for key in person.verifierKeys {
                upsert(key) { if !$0.contactNames.contains(name) { $0.contactNames.append(name) } }
            }
        }
        return result
    }
}
