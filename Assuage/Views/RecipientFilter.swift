import AssuageCore

/// A quick-select category for the extra-recipients table's "Select" menu, grouping
/// added recipients by key type — the recipient-side mirror of `KeyFilter`.
enum RecipientFilter: CaseIterable, Identifiable {
    case age
    case postQuantum
    case ssh

    var id: Self { self }

    var title: String {
        switch self {
        case .age: return "Age"
        case .postQuantum: return "Post-quantum"
        case .ssh: return "SSH"
        }
    }

    func matches(_ recipient: AgeRecipient) -> Bool {
        switch self {
        case .age: return recipient.kind != .sshEd25519 && !recipient.isPostQuantum
        case .postQuantum: return recipient.isPostQuantum
        case .ssh: return recipient.kind == .sshEd25519
        }
    }

    /// The categories that match at least one of `recipients`.
    static func available(in recipients: [AgeRecipient]) -> [RecipientFilter] {
        allCases.filter { filter in recipients.contains(where: filter.matches) }
    }
}
