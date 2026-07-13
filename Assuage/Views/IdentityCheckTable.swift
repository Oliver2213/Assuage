import SwiftUI
import AssuageCore

/// A titled table for selecting a subset of identities: a checkbox column plus the
/// key's label/recipient and storage, with a Select menu (All / by category / None).
/// Used to pick recipients (Encrypt) and identities to try (Decrypt), each passing
/// its own `title`.
struct IdentityCheckTable: View {
    let identities: [AgeIdentity]
    @Binding var selection: Set<UUID>
    let title: LocalizedStringKey
    /// Show a Touch ID marker for presence-protected keys (used when decrypting).
    var showsPresence = false

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Table(identities) {
                    TableColumn("") { identity in
                        Toggle(isOn: binding(for: identity)) { EmptyView() }
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(identity.displayName)
                    }
                    .width(24)

                    TableColumn("Key") { identity in
                        HStack(spacing: 6) {
                            IdentityLabel(identity: identity)
                            if showsPresence && identity.requiresPresence {
                                Image(systemName: "touchid")
                                    .foregroundStyle(.secondary)
                                    .help("Using this key prompts for Touch ID or your passcode.")
                            }
                        }
                    }

                    TableColumn("Storage") { identity in
                        Text(identity.sourceDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120, maxHeight: 240)
                .accessibilityLabel(title)

                HStack(spacing: 8) {
                    // A plain menu (not a split button) so VoiceOver reaches every option.
                    Menu("Select") {
                        Button("All") { selection = Set(identities.map(\.id)) }
                        ForEach(KeyFilter.available(in: identities)) { filter in
                            Button(filter.title) { selection = Set(identities.filter(filter.matches).map(\.id)) }
                        }
                        Divider()
                        Button("None") { selection.removeAll() }
                    }
                    .fixedSize()
                    Spacer()
                    Text("\(selection.count) of \(identities.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
            .padding(4)
        }
    }

    private func binding(for identity: AgeIdentity) -> Binding<Bool> {
        Binding(
            get: { selection.contains(identity.id) },
            set: { isOn in
                if isOn { selection.insert(identity.id) }
                else { selection.remove(identity.id) }
            }
        )
    }
}
