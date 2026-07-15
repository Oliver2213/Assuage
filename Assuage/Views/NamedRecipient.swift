import Foundation
import AssuageCore

/// A recipient plus an optional display name, for the ad-hoc recipients you add by
/// pasting a key, loading a recipients file (its `# name` comments), or — later —
/// fetching a code-forge URL.
struct NamedRecipient: Identifiable, Hashable {
    let recipient: AgeRecipient
    var name: String?
    /// The stable identifier of the contact this key came from, when it came from one —
    /// so a recipient stays tied to a specific card, never an ambiguous display name.
    var contactID: String?
    var id: String { recipient.id }

    /// Parse a recipients file: each `age1…` / `ssh-…` line becomes a recipient,
    /// named by the `# name` comment immediately above it, if any. Blank and
    /// unparseable lines are skipped.
    static func parse(recipientsFile text: String) -> [NamedRecipient] {
        var result: [NamedRecipient] = []
        var pendingName: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let name = line.dropFirst().trimmingCharacters(in: .whitespaces)
                pendingName = name.isEmpty ? nil : name
                continue
            }
            if let recipient = try? AgeRecipient(parsing: line) {
                result.append(NamedRecipient(recipient: recipient, name: pendingName))
            }
            pendingName = nil
        }
        return result
    }
}
