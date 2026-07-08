import SwiftUI
import CypherdexCore

/// A table for selecting a subset of identities: a checkbox column plus the key's
/// label/recipient and storage, with Select All / Deselect All controls. Used to
/// pick recipients (Encrypt) and identities to try (Decrypt).
struct IdentityCheckTable: View {
    let identities: [AgeIdentity]
    @Binding var selection: Set<UUID>
    /// Show a Touch ID marker for presence-protected keys (used when decrypting).
    var showsPresence = false

    private var allSelected: Bool { !identities.isEmpty && selection.count == identities.count }
    private var noneSelected: Bool { selection.isEmpty }

    var body: some View {
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

            HStack(spacing: 8) {
                Button("Select All") { selection = Set(identities.map(\.id)) }
                    .disabled(allSelected)
                Button("Deselect All") { selection.removeAll() }
                    .disabled(noneSelected)
                Spacer()
                Text("\(selection.count) of \(identities.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
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
