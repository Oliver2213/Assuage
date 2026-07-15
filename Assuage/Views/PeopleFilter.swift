/// The People view's filter — which recipients to show. Defaults to only people we
/// can actually encrypt to, since an address book is mostly people without keys.
enum PeopleFilter: String, CaseIterable, Identifiable {
    case withKeys, all, age, ssh, postQuantum, verifier, forge
    var id: Self { self }

    var title: String {
        switch self {
        case .withKeys: "With encryption keys"
        case .all: "All contacts"
        case .age: "Age keys"
        case .ssh: "SSH keys"
        case .postQuantum: "Post-quantum keys"
        case .verifier: "Verifier keys"
        case .forge: "Forge links"
        }
    }

    func matches(_ person: Person) -> Bool {
        switch self {
        case .withKeys: person.canEncrypt
        case .all: true
        case .age: !person.ageRecipients.isEmpty
        case .ssh: !person.sshRecipients.isEmpty
        case .postQuantum: !person.postQuantumRecipients.isEmpty
        case .verifier: !person.verifierKeys.isEmpty
        case .forge: !person.forgeURLs.isEmpty
        }
    }
}
