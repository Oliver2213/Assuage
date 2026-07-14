import AssuageCore

/// How public keys are rendered in the UI. Display only — copy, export, and the
/// pasteboard always use the full recipient string.
enum PublicKeyDisplay: String, CaseIterable, Identifiable {
    case abbreviated, full
    var id: Self { self }

    var title: String {
        switch self {
        case .abbreviated: "Abbreviated"
        case .full: "Full"
        }
    }
}

extension PublicKeyDisplay {
    /// Shorten a public key for the abbreviated style: the first 12 characters
    /// (enough to keep the type prefix, e.g. `age1pq1…`) plus the last 4, joined by
    /// an ellipsis. Short keys are returned whole. The single source for both age
    /// recipients and note verifier keys.
    static func abbreviate(_ key: String) -> String {
        guard key.count > 20 else { return key }
        return "\(key.prefix(12))…\(key.suffix(4))"
    }
}

extension AgeRecipient {
    /// The recipient shortened for the abbreviated style. See `PublicKeyDisplay.abbreviate`.
    var abbreviatedDisplay: String { PublicKeyDisplay.abbreviate(encoding) }
}
