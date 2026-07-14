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
    /// The contact's plain URLs that aren't our key fields — candidate code-forge
    /// profiles we can fetch `.keys` from on demand.
    var forgeURLs: [URL]
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

    var ageRecipients: [AgeRecipient] { recipients.filter { $0.kind != .sshEd25519 } }
    var sshRecipients: [AgeRecipient] { recipients.filter { $0.kind == .sshEd25519 } }
    var postQuantumRecipients: [AgeRecipient] { recipients.filter(\.isPostQuantum) }

    /// Whether we hold anything we could encrypt to.
    var hasEncryptionKey: Bool { !recipients.isEmpty }
}

extension Person {
    /// Build a person from a fetched contact, decoding our key fields out of its URL
    /// addresses and keeping the rest as candidate forge links. `nonisolated` so the
    /// off-main contacts fetch can build people.
    nonisolated init(contact: CNContact) {
        var recipients: [AgeRecipient] = []
        var verifierKeys: [VerifierKey] = []
        var forgeURLs: [URL] = []

        for labeled in contact.urlAddresses {
            let value = labeled.value as String
            switch ContactKeyField.decode(value: value) {
            case .recipient(let recipient): recipients.append(recipient)
            case .verifier(let verifier): verifierKeys.append(verifier)
            case nil:
                // Not one of ours — a normal URL, a possible code-forge profile.
                if let url = URL(string: value) { forgeURLs.append(url) }
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
            recipients: recipients,
            verifierKeys: verifierKeys,
            source: .contact(identifier: contact.identifier)
        )
    }
}
