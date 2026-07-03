import SwiftUI
import AppKit
import CypherdexCore

/// A detailed row for one identity, with export / copy / delete actions.
struct IdentityRow: View {
    let identity: AgeIdentity
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: identity.sourceIcon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(identity.displayName)
                    .font(.headline)
                Spacer()
                Text(identity.kindDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            LabeledContent("Public key") {
                Text(identity.recipient.encoding)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LabeledContent("Created", value: identity.created.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Storage", value: identity.sourceDescription)
            if let accessControl = identity.accessControl {
                LabeledContent("Requires", value: accessControl.displayName)
            }

            HStack(spacing: 8) {
                Button("Copy Recipient", systemImage: "doc.on.doc") {
                    copyToPasteboard(identity.recipient.encoding)
                }
                Button("Export Public Key…", systemImage: "square.and.arrow.up") {
                    SavePanel.save(text: identity.publicKeyFile(), suggestedName: "\(fileBase).pub")
                }
                Button("Export Identity…", systemImage: "key") {
                    SavePanel.save(text: identity.ageFormatted(), suggestedName: "\(fileBase).txt")
                }
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private var fileBase: String {
        identity.displayName.replacingOccurrences(of: " ", with: "-")
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
