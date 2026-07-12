import AssuageCore

/// How public keys are rendered in the UI. Display only — copy, export, and the
/// pasteboard always use the full recipient string.
enum PublicKeyDisplay: String, CaseIterable, Identifiable {
    case abbreviated, full
    var id: Self { self }

    var title: String {
        switch self {
        case .abbreviated: return "Abbreviated"
        case .full: return "Full"
        }
    }
}

extension AgeRecipient {
    /// The recipient shortened for the abbreviated style: the first 12 characters
    /// (enough to keep the type prefix, e.g. `age1pq1…`) plus the last 4, joined by
    /// an ellipsis. Short recipients are returned whole.
    var abbreviatedDisplay: String {
        let s = encoding
        guard s.count > 20 else { return s }
        return "\(s.prefix(12))…\(s.suffix(4))"
    }
}
