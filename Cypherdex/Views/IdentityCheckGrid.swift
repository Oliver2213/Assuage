import SwiftUI
import CypherdexCore

/// A self-sizing checkbox grid for selecting a subset of identities.
/// Two columns: a checkbox and the identity label.
struct IdentityCheckGrid: View {
    let identities: [AgeIdentity]
    @Binding var selection: Set<UUID>
    /// Show a Touch ID marker for presence-protected keys (used when decrypting).
    var showsPresence = false

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(identities) { identity in
                GridRow {
                    Toggle(identity.displayName, isOn: binding(for: identity))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    HStack(spacing: 6) {
                        IdentityLabel(identity: identity)
                        if showsPresence && identity.requiresPresence {
                            Image(systemName: "touchid")
                                .foregroundStyle(.secondary)
                                .help("Using this key prompts for Touch ID or your passcode.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
