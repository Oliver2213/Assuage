import SwiftUI
import AssuageCore

/// A titled table for choosing which signing keys to sign a note with: a checkbox
/// column plus the signer's name / key ID and storage, with a Select All / None
/// menu and a count. The note gets one signature per checked key. Mirrors
/// `IdentityCheckTable`, minus the age-specific category filters.
struct SigningKeyCheckTable: View {
    let signingKeys: [SigningKey]
    @Binding var selection: Set<UUID>
    let title: LocalizedStringKey

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Table(signingKeys) {
                    TableColumn("") { signer in
                        Toggle(isOn: binding(for: signer)) { EmptyView() }
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(signer.displayName)
                    }
                    .width(24)

                    TableColumn("Signer") { signer in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(signer.name)
                            Text("Key ID \(signer.keyIDHex)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    TableColumn("Storage") { signer in
                        Text(signer.storageDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 100, maxHeight: 200)
                .accessibilityLabel(title)

                HStack(spacing: 8) {
                    // A plain menu (not a split button) so VoiceOver reaches every option.
                    Menu("Select") {
                        Button("All") { selection = Set(signingKeys.map(\.id)) }
                        Button("None") { selection.removeAll() }
                    }
                    .fixedSize()
                    Spacer()
                    Text("\(selection.count) of \(signingKeys.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
            .padding(4)
        }
    }

    private func binding(for signer: SigningKey) -> Binding<Bool> {
        Binding(
            get: { selection.contains(signer.id) },
            set: { isOn in
                if isOn { selection.insert(signer.id) } else { selection.remove(signer.id) }
            }
        )
    }
}
