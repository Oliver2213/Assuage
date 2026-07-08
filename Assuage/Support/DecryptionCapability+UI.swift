import SwiftUI
import CypherdexCore

/// UI presentation for a header-only decryptability verdict, kept out of the core
/// library. Shown on the Decrypt inspector so you can tell at a glance whether a
/// file is yours to open — computed from public key tags, without unlocking anything.
extension DecryptionCapability {
    var statusText: String {
        switch self {
        case .decryptable(let identities):
            if identities.count == 1 {
                return String(localized: "You can decrypt this — matches “\(identities[0].displayName)”")
            }
            return String(localized: "You can decrypt this — ^[\(identities.count) of your keys](inflect: true) match")
        case .undetermined:
            return String(localized: "You may be able to decrypt this")
        case .passphraseRequired:
            return String(localized: "Passphrase required")
        case .noMatchingKey:
            return String(localized: "You don’t have a key for this file")
        }
    }

    var statusIcon: String {
        switch self {
        case .decryptable: return "checkmark.seal.fill"
        case .undetermined: return "questionmark.circle"
        case .passphraseRequired: return "key.fill"
        case .noMatchingKey: return "xmark.seal"
        }
    }

    var statusColor: Color {
        switch self {
        case .decryptable: return .green
        case .undetermined: return .orange
        case .passphraseRequired, .noMatchingKey: return .secondary
        }
    }
}
