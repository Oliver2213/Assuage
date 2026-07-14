import SwiftUI
import AssuageCore

/// The single place a public key renders in the UI — an age recipient or a note
/// verifier key. Honors the "show public keys as" preference: full is
/// text-selectable, abbreviated shows the whole key on hover. Copy and export
/// always use the full string — never route those through this view.
struct PublicKeyText: View {
    private let full: String
    private let abbreviated: String
    @AppStorage(PreferenceKeys.publicKeyDisplay) private var style: PublicKeyDisplay = .abbreviated

    init(recipient: AgeRecipient) {
        full = recipient.encoding
        abbreviated = recipient.abbreviatedDisplay
    }

    /// Render any public key string (e.g. an encoded verifier key).
    init(key: String) {
        full = key
        abbreviated = PublicKeyDisplay.abbreviate(key)
    }

    var body: some View {
        Group {
            if style == .full {
                Text(full)
                    .textSelection(.enabled)
            } else {
                // Not selectable — selecting would copy the abbreviated form.
                Text(abbreviated)
            }
        }
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
        .help(full)
    }
}
