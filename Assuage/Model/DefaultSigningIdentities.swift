import Foundation

/// Which note signing keys to sign with by default — used both by the "Sign Note"
/// Service (which signs without any UI) and as the pre-selection in the in-app Sign
/// view. Ordering is oldest-first, so "first" is your earliest signing key and
/// "last" is your newest.
enum DefaultSigningIdentities: String, CaseIterable, Identifiable {
    /// Your earliest-created signing key only.
    case first
    /// Your most recently created signing key only.
    case last
    /// Every signing key you hold — one signature each.
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .first: return "First key"
        case .last: return "Last key"
        case .all: return "All keys"
        }
    }

    /// The current preference, defaulting to `.all`.
    static var current: DefaultSigningIdentities {
        UserDefaults.standard.string(forKey: PreferenceKeys.defaultSigningIdentities)
            .flatMap(Self.init(rawValue:)) ?? .all
    }

    /// The keys to sign with, chosen from `keys` ordered oldest-first so "first" and
    /// "last" are stable regardless of the order the keychain hands them back.
    func select(from keys: [SigningKey]) -> [SigningKey] {
        let ordered = keys.sorted { $0.created < $1.created }
        switch self {
        case .first: return Array(ordered.prefix(1))
        case .last: return Array(ordered.suffix(1))
        case .all: return ordered
        }
    }
}
