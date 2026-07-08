import AssuageCore

/// The user-facing keychain storage choice, shared by the generate and import
/// flows. Resolves to a concrete `KeychainProtection` given an auth flavor.
/// Ordered secure-by-default first.
enum KeychainStorageMode: CaseIterable, Identifiable {
    case authenticated, local, synced

    var id: Self { self }

    var title: String {
        switch self {
        case .authenticated: return "Local + Touch ID"
        case .local: return "Local"
        case .synced: return "iCloud (synced)"
        }
    }

    func protection(auth: KeychainAuth) -> KeychainProtection {
        switch self {
        case .authenticated: return .authenticated(auth)
        case .local: return .local
        case .synced: return .synced
        }
    }
}
