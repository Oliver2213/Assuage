import Foundation

/// A single X25519 secret key found in an identity file, validated and paired
/// with its derived public recipient — but not yet imported. The UI turns each
/// of these into an editable row (name, sync) before committing to the store.
public struct ImportableKey: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// The validated `AGE-SECRET-KEY-1…` secret.
    public let secretKey: String
    /// The public recipient derived from the secret, for display.
    public let recipient: AgeRecipient

    public init(id: UUID = UUID(), secretKey: String, recipient: AgeRecipient) {
        self.id = id
        self.secretKey = secretKey
        self.recipient = recipient
    }
}

extension AgeIdentity {
    /// Parse every valid X25519 secret key out of identity-file text. Comment
    /// lines, blank lines, and anything that isn't a well-formed
    /// `AGE-SECRET-KEY-1…` secret are skipped, so a file with junk or unsupported
    /// key types still yields the keys we can actually import.
    public static func importableKeys(from text: String) -> [ImportableKey] {
        var keys: [ImportableKey] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("AGE-SECRET-KEY-1"),
                  let parsed = try? parseX25519(trimmed) else { continue }
            keys.append(ImportableKey(
                secretKey: parsed.string,
                recipient: AgeRecipient(kind: .x25519, encoding: parsed.recipient.string)
            ))
        }
        return keys
    }
}
