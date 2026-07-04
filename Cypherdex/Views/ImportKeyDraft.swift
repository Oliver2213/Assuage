import Foundation
import CypherdexCore

/// One key being reviewed in the import sheet: the parsed key plus the user's
/// editable choices (include, name, sync) and whether we already hold it.
struct ImportKeyDraft: Identifiable {
    let key: ImportableKey
    var id: UUID { key.id }
    var include = true
    var name: String
    var sync: Bool
    /// True when a key with this recipient is already in the keychain.
    var alreadyExists = false
}
