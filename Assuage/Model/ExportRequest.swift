import Foundation
import AssuageCore

/// A request to export one or more identities as a single protected file. Wraps
/// the identities so it can drive a `.sheet(item:)`.
struct ExportRequest: Identifiable {
    let id = UUID()
    let identities: [AgeIdentity]
}
