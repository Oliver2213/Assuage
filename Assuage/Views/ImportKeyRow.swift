import SwiftUI
import AssuageCore

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
                    PublicKeyText(recipient: draft.key.recipient)
                        .foregroundStyle(.secondary)
                    if draft.alreadyExists {
                        Label("Already in your keychain", systemImage: "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
            }

            if draft.key.recipient.kind == .secureEnclave {
                // Device-bound: storage isn't a choice, so show a fixed tag
                // rather than a picker that could imply syncing.
                Label("Secure Enclave", systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("Device-bound key. It stays in this Mac’s Secure Enclave and can’t be moved or synced.")
            } else {
                Picker("Storage", selection: $draft.storage) {
                    ForEach(KeyStorage.keychainCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .help("Where this key is stored: hardware-protected, local, or synced via iCloud")
            }
        }
        .opacity(draft.include ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}
