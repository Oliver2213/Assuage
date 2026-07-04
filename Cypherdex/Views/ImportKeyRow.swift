import SwiftUI
import CypherdexCore

/// One editable row in the import review list: a checkbox to include the key, a
/// name field, its public recipient, and a keychain-storage menu. Bound to a
/// `Draft` so edits flow straight back to the sheet's state.
struct ImportKeyRow: View {
    @Binding var draft: ImportKeyDraft

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("Import this key", isOn: $draft.include)
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $draft.name, prompt: Text("Name"))
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text(draft.key.recipient.encoding)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if draft.alreadyExists {
                        Label("Already in your keychain", systemImage: "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
            }

            Picker("Storage", selection: $draft.storage) {
                ForEach(KeychainStorageMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .help("Where this key is stored: hardware-protected, local, or synced via iCloud")
        }
        .opacity(draft.include ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}
