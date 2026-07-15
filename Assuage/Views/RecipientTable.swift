import SwiftUI
import AssuageCore

/// A titled, checkbox table of the ad-hoc recipients you've added (pasted, from a
/// file, a forge URL, or a contact): each shows its name over its public key, can be
/// checked to include in the encryption, copied, or removed. A Select menu (All / by
/// key type / None) mirrors the identity table for consistency.
struct RecipientTable: View {
    @Binding var recipients: [NamedRecipient]
    @Binding var selection: Set<String>
    let title: LocalizedStringKey

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Table(recipients) {
                    TableColumn("") { named in
                        Toggle(isOn: binding(for: named)) { EmptyView() }
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(named.name ?? named.recipient.encoding)
                    }
                    .width(24)

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

                HStack(spacing: 8) {
                    // A plain menu (not a split button) so VoiceOver reaches every option.
                    Menu("Select") {
                        Button("All") { selection = Set(recipients.map(\.id)) }
                        ForEach(RecipientFilter.available(in: recipients.map(\.recipient))) { filter in
                            Button(filter.title) {
                                selection = Set(recipients.filter { filter.matches($0.recipient) }.map(\.id))
                            }
                        }
                        Divider()
                        Button("None") { selection.removeAll() }
                    }
                    .fixedSize()
                    Spacer()
                    Text("\(selectedCount) of \(recipients.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
            .padding(4)
        }
    }

    private var selectedCount: Int {
        recipients.filter { selection.contains($0.id) }.count
    }

    private func binding(for named: NamedRecipient) -> Binding<Bool> {
        Binding(
            get: { selection.contains(named.id) },
            set: { isOn in
                if isOn { selection.insert(named.id) } else { selection.remove(named.id) }
            }
        )
    }

    private func remove(_ named: NamedRecipient) {
        recipients.removeAll { $0.id == named.id }
        selection.remove(named.id)
    }
}
