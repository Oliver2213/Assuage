import SwiftUI
import AssuageCore

/// The single place a public key renders in the UI. Honors the "show public keys
/// as" preference: full is text-selectable, abbreviated shows the whole key on
/// hover. Copy and export always use the full string — never route those through
/// this view.
struct PublicKeyText: View {
    let recipient: AgeRecipient
    @AppStorage(PreferenceKeys.publicKeyDisplay) private var style: PublicKeyDisplay = .abbreviated

    var body: some View {
        Group {
            if style == .full {
                Text(recipient.encoding)
                    .textSelection(.enabled)
            } else {
                // Not selectable — selecting would copy the abbreviated form.
                Text(recipient.abbreviatedDisplay)
            }
        }
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
        .help(recipient.encoding)
    }
}
