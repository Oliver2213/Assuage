import Foundation
import Contacts
import AssuageCore

/// A person you can encrypt to or verify notes from — a unified view over a system
/// Contact (the usual case) or, later, an app-only record. Their public keys, emails,
/// and code-forge links all come from the contact card; Assuage keeps no parallel
/// store of them (private keys live in the keychain, not here).
nonisolated struct Person: Identifiable, Hashable, Sendable {
    /// Where this record comes from, so the UI can link back and show provenance.
    enum Source: Hashable, Sendable {
        case contact(identifier: String)
        case app
    }

    let id: String
    var name: String
    var emails: [Email]
    /// The contact's plain URLs that aren't our key or revocation fields — candidate
    /// code-forge profiles we can fetch `.keys` from on demand.
    var forgeURLs: [URL]
    /// Published revoked-key lists we can check to drop retired keys.
    var revocationLists: [RevocationList]
    /// Age and SSH recipients parsed from the card.
    var recipients: [AgeRecipient]
    /// Note verifier keys parsed from the card.
    var verifierKeys: [VerifierKey]
    var source: Source

    struct Email: Hashable, Sendable {
        /// A human label (Home / Work / …), already de-coded from Contacts' raw label.
        var label: String?
        var address: String
    }

    /// A URL the contact publishes listing keys of one kind they've revoked. Checking
    /// it removes any matching key we hold — fetched or hand-added. This is the only
    /// thing that removes a key on sync; a forge fetch only ever adds.
    struct RevocationList: Identifiable, Hashable, Sendable {
        var kind: ContactRevocationField
        var url: URL
        var id: String { "\(kind.rawValue)\(url.absoluteString)" }
    }

    var ageRecipients: [AgeRecipient] { recipients.filter { $0.kind != .sshEd25519 } }
    var sshRecipients: [AgeRecipient] { recipients.filter { $0.kind == .sshEd25519 } }
    var postQuantumRecipients: [AgeRecipient] { recipients.filter(\.isPostQuantum) }

    /// Whether we hold any key we could encrypt to (an age or SSH recipient).
    var canEncrypt: Bool { !recipients.isEmpty }

    /// Whether we could encrypt to this contact post-quantum (a PQ age recipient).
    var canEncryptPostQuantum: Bool { !postQuantumRecipients.isEmpty }

    /// Whether we could verify this contact's signed notes (a note verifier key).
    var canVerifyNotes: Bool { !verifierKeys.isEmpty }
}

extension Person {
    /// Build a person from a fetched contact, decoding our key fields out of its URL
    /// addresses and keeping the rest as candidate forge links. `nonisolated` so the
    /// off-main contacts fetch can build people.
    nonisolated init(contact: CNContact) {
        var recipients: [AgeRecipient] = []
        var verifierKeys: [VerifierKey] = []
        var revocationLists: [RevocationList] = []
        var forgeURLs: [URL] = []

        for labeled in contact.urlAddresses {
            let value = labeled.value as String
            // Keys are identified by their value's scheme; revocation lists by their
            // label (their value is a plain URL). Everything else is a forge candidate.
            switch ContactKeyField.decode(value: value) {
            case .recipient(let recipient): recipients.append(recipient)
            case .verifier(let verifier): verifierKeys.append(verifier)
            case nil:
                if let kind = ContactRevocationField(label: labeled.label ?? ""), let url = URL(string: value) {
                    revocationLists.append(RevocationList(kind: kind, url: url))
                } else if let url = URL(string: value) {
                    forgeURLs.append(url)
                }
            }
        }

        self.init(
            id: contact.identifier,
            name: CNContactFormatter.string(from: contact, style: .fullName) ?? contact.identifier,
            emails: contact.emailAddresses.map {
                Email(label: $0.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) },
                      address: $0.value as String)
            },
            forgeURLs: forgeURLs,
            revocationLists: revocationLists,
            recipients: recipients,
            verifierKeys: verifierKeys,
            source: .contact(identifier: contact.identifier)
        )
    }
}
