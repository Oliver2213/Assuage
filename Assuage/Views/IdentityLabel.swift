import SwiftUI
import CypherdexCore

/// A compact two-line identity label: name over its recipient string.
struct IdentityLabel: View {
    let identity: AgeIdentity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: identity.sourceIcon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.displayName)
                Text(identity.recipient.encoding)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
