import SwiftUI
import AssuageCore

struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var identitiesToDelete: [AgeIdentity] = []
    @State private var isDeleteConfirmationPresented = false
    @AppStorage(PreferenceKeys.requireAuthToDelete) private var requireAuthToDelete = false

    var body: some View {
        Group {
            if model.identities.isEmpty {
                ContentUnavailableView {
                    Label("No Keys Yet", systemImage: "key")
                } description: {
                    Text("Generate an age keypair to start encrypting and decrypting. Secure Enclave keys never leave this Mac.")
                } actions: {
                    Button("Generate age Keypair…", systemImage: "plus") { model.showGenerateSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
                }
            } else {
                @Bindable var model = model
                VStack(spacing: 0) {
                    List(selection: $model.selectedKeyIDs) {
                        ForEach(model.identities) { identity in
                            IdentityRow(identity: identity) { requestDelete([identity]) }
                                .tag(identity.id)
                        }
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        selectionMenu(for: model.identities.filter { ids.contains($0.id) })
                    } primaryAction: { ids in
                        // Double-click a single row to edit it.
                        if ids.count == 1, let key = model.identities.first(where: { ids.contains($0.id) }) {
                            model.editingKey = key
                        }
                    }
                    // ⌘C copies the selected keys' recipients (always the full keys).
                    .onCopyCommand {
                        guard !model.selectedKeys.isEmpty else { return [] }
                        return [NSItemProvider(object: model.recipientsFile(for: model.selectedKeys) as NSString)]
                    }
                    Divider()
                    Text("Keys live in your keychain. A local key stays on this Mac; a synced key shares to your other devices via iCloud Keychain; a Touch ID–protected key stays on this Mac and is sealed by the Secure Enclave, so its secret can’t be read at rest without authenticating. Secure Enclave keys never sync — they only work on the Mac that created them. You can export any key for backup, but an exported Secure Enclave key still only works on that Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .navigationTitle("Keys")
        .toolbar {
            ToolbarItemGroup {
                Button("Edit Key…", systemImage: "pencil") { model.editingKey = model.singleSelectedKey }
                    .disabled(model.singleSelectedKey == nil)
                Menu {
                    Button("Copy Recipients", systemImage: "doc.on.doc") { model.copyRecipients(for: model.selectedKeys) }
                    Button("Export Recipients…", systemImage: "square.and.arrow.up") { model.exportRecipients(for: model.selectedKeys) }
                } label: {
                    Label("Recipients", systemImage: "person.2")
                }
                .labelStyle(.titleAndIcon)
                .disabled(model.selectedKeys.isEmpty)
                Button("Export Identities…", systemImage: "key") { model.exportingKeys = ExportRequest(identities: model.selectedKeys) }
                    .disabled(model.selectedKeys.isEmpty)
                Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(model.selectedKeys) }
                    .disabled(model.selectedKeys.isEmpty)
                Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
                Button("Generate…", systemImage: "plus") { model.showGenerateSheet = true }
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(identitiesToDelete.count == 1 ? "Delete Key" : "Delete \(identitiesToDelete.count) Keys",
                   role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(identitiesToDelete.count == 1
                 ? "This can’t be undone. Export the key first if you might need it again."
                 : "This can’t be undone. Export the keys first if you might need them again.")
        }
    }

    /// The multi-select actions for the right-clicked selection. Labels adapt to a
    /// single key vs. several; `contextMenu(forSelectionType:)` selects the clicked
    /// row first, so the visible checkboxes always match what an action affects.
    @ViewBuilder
    private func selectionMenu(for keys: [AgeIdentity]) -> some View {
        if !keys.isEmpty {
            let one = keys.count == 1
            Button("Encrypt to \(one ? "This Recipient" : "These \(keys.count) Recipients")", systemImage: "lock") {
                model.composeEncrypt(to: keys)
            }
            Button("Decrypt with \(one ? "This Identity" : "These \(keys.count) Identities")", systemImage: "lock.open") {
                model.composeDecrypt(with: keys)
            }
            Divider()
            Button("Copy \(one ? "Recipient" : "Recipients")", systemImage: "doc.on.doc") {
                model.copyRecipients(for: keys)
            }
            Button("Export \(one ? "Public Key…" : "Public Keys…")", systemImage: "square.and.arrow.up") {
                model.exportRecipients(for: keys)
            }
            Button("Export \(one ? "Identity…" : "Identities…")", systemImage: "key") {
                model.exportingKeys = ExportRequest(identities: keys)
            }
            if one {
                Divider()
                Button("Edit…", systemImage: "pencil") { model.editingKey = keys.first }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(keys) }
        }
    }

    private var deleteConfirmationTitle: String {
        identitiesToDelete.count == 1
            ? "Delete “\(identitiesToDelete.first?.displayName ?? "")”?"
            : "Delete \(identitiesToDelete.count) keys?"
    }

    private func requestDelete(_ identities: [AgeIdentity]) {
        guard !identities.isEmpty else { return }
        identitiesToDelete = identities
        isDeleteConfirmationPresented = true
    }

    /// Authenticate once when the preference asks for it, then delete every target.
    private func performDelete() {
        let targets = identitiesToDelete
        Task {
            if requireAuthToDelete {
                let reason = targets.count == 1
                    ? String(localized: "Authenticate to delete the key “\(targets[0].displayName)”.")
                    : String(localized: "Authenticate to delete \(targets.count) keys.")
                guard await Authentication.authorize(reason: reason) else { return }
            }
            for identity in targets { model.delete(identity) }
        }
    }
}
