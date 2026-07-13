import SwiftUI
import AssuageCore

/// A titled table of the ad-hoc recipients you've added (pasted, from a file, or a
/// URL): each shows its name over its public key, is copyable, and can be removed.
struct RecipientTable: View {
    @Binding var recipients: [NamedRecipient]
    let title: LocalizedStringKey

    var body: some View {
        GroupBox(title) {
            Table(recipients) {
                TableColumn("Recipient") { named in
                    VStack(alignment: .leading, spacing: 1) {
                        if let name = named.name {
                            Text(name)
                        }
                        PublicKeyText(recipient: named.recipient)
                    }
                    .contextMenu {
                        Button("Copy Public Key", systemImage: "doc.on.doc") {
                            Pasteboard.copy(named.recipient.encoding, sensitive: false)
                        }
                        Button("Remove", systemImage: "xmark.circle.fill", role: .destructive) {
                            remove(named)
                        }
                    }
                }
                TableColumn("") { named in
                    Button("Remove recipient", systemImage: "xmark.circle.fill") { remove(named) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .width(28)
            }
            .frame(minHeight: 80, maxHeight: 200)
            .accessibilityLabel(title)
            .padding(4)
        }
    }

    private func remove(_ named: NamedRecipient) {
        recipients.removeAll { $0.id == named.id }
    }
}
