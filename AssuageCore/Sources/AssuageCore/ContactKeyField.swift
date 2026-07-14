import Foundation

/// The convention for embedding a public key on a contact card, used identically
/// for your own card and other people's. A key is stored as a custom-labeled URL
/// value whose scheme names the key kind and whose payload is the key itself,
/// percent-encoded so the whole thing is a valid, URL-safe string:
///
///     age-public-key:age1qx…                 (age recipients — bech32, already safe)
///     ssh-public-key:ssh-ed25519%20AAAA…     (SSH lines — spaces/base64 encoded)
///     verifier-key:example.com%2Fbob%2B…     (signed-note verifier keys — `+`/`/` encoded)
///
/// The label and the value's scheme are the same string, so a card that loses its
/// label (or is shared as a vCard) still round-trips from the value alone.
public enum ContactKeyField {
    /// The kind of key a field holds — also the field's label and URL scheme.
    public enum Kind: String, Sendable, CaseIterable {
        case ageRecipient = "age-public-key"
        case sshRecipient = "ssh-public-key"
        case verifierKey = "verifier-key"
    }

    /// A decoded contact key field.
    public enum Decoded: Sendable, Hashable {
        case recipient(AgeRecipient)
        case verifier(VerifierKey)
    }

    /// The label + URL value to store on a contact for a recipient. SSH recipients
    /// get the `ssh-public-key` label; every other age kind gets `age-public-key`.
    public static func entry(for recipient: AgeRecipient) -> (label: String, value: String) {
        let kind: Kind = recipient.kind == .sshEd25519 ? .sshRecipient : .ageRecipient
        return entry(kind: kind, payload: recipient.encoding)
    }

    /// The label + URL value to store on a contact for a note verifier key.
    public static func entry(for verifier: VerifierKey) -> (label: String, value: String) {
        entry(kind: .verifierKey, payload: verifier.encoded)
    }

    /// Decode a contact URL field's value into a key, or `nil` if it isn't one of
    /// ours. The value's scheme is authoritative; the field's label isn't needed.
    public static func decode(value: String) -> Decoded? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        guard let kind = Kind(rawValue: String(value[..<colon])) else { return nil }
        let payload = decodePayload(String(value[value.index(after: colon)...]))
        switch kind {
        case .ageRecipient, .sshRecipient:
            return (try? AgeRecipient(parsing: payload)).map(Decoded.recipient)
        case .verifierKey:
            return (try? VerifierKey(parsing: payload)).map(Decoded.verifier)
        }
    }

    /// Whether a field label is one of ours — for skipping our own key entries when
    /// scanning a contact's URLs for code-forge profiles to fetch keys from.
    public static func isKeyLabel(_ label: String) -> Bool {
        Kind(rawValue: label) != nil
    }

    // MARK: - Encoding

    private static func entry(kind: Kind, payload: String) -> (label: String, value: String) {
        (kind.rawValue, "\(kind.rawValue):\(encodePayload(payload))")
    }

    /// Percent-encode everything except RFC 3986 unreserved characters, so the
    /// result is unambiguous (colons, `+`, `/`, `=`, spaces all encoded) and splits
    /// cleanly on its first colon. age bech32 keys are all-unreserved, so they stay
    /// human-readable; SSH and verifier keys get encoded.
    private static func encodePayload(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    private static func decodePayload(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
