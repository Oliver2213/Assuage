/// The custom URL-field labels Assuage uses to mark a contact's *revoked-key lists* —
/// one per key kind. A revocation list is a URL the contact publishes that names keys
/// they've retired; syncing it removes any matching key we hold, whether we fetched it
/// from a forge or the user added it by hand.
///
/// Unlike a key field (whose kind is tagged in the URL *value*, so it survives a lost
/// label), a revocation URL is stored as a plain, clickable `https://…` value and is
/// recognized by its *label*. That keeps the card tidy, at one cost: if the label is
/// ever stripped (some vCard exports drop custom labels), the value is just a URL and
/// would look like an ordinary forge link. Callers guard against that — a URL is only
/// treated as a revocation list when its label matches, never by its value.
public enum ContactRevocationField: String, CaseIterable, Sendable {
    case age = "revoked-age-keys-url"
    case ssh = "revoked-ssh-keys-url"
    case verifier = "revoked-verifier-keys-url"

    /// The revocation kind a field label names, or `nil` if the label isn't one of ours.
    public init?(label: String) {
        self.init(rawValue: label)
    }

    /// The custom URL-field label to store this revocation list under.
    public var label: String { rawValue }

    /// A human name for the kind of keys this list revokes ("age", "SSH", "verifier").
    public var keyTypeName: String {
        switch self {
        case .age: "age"
        case .ssh: "SSH"
        case .verifier: "verifier"
        }
    }
}
