import SwiftUI

/// When to require authentication before a private key's secret leaves the app
/// (reveal / export / copy). Stored via `@AppStorage`.
enum ExportAuthPolicy: String, CaseIterable, Identifiable {
    /// Prompt for every key, regardless of where it lives.
    case always
    /// Prompt only for keychain (X25519) keys, whose exported secret works
    /// anywhere. Secure Enclave exports are device-locked blobs, so they skip it.
    case keychainOnly
    /// Never prompt.
    case never

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .always: return "Always"
        case .keychainOnly: return "Only keychain keys"
        case .never: return "Never"
        }
    }
}
