import SwiftUI

/// A small caution line — a warning-triangle icon plus text in orange — used under
/// the key sheets' forms for reversible-but-risky choices. Shared so the generate
/// and edit sheets read identically.
struct WarningLabel: View {
    private let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
