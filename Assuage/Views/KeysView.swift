import SwiftUI
import AssuageCore

/// The Keys panel: an Encryption / Signing sub-tab over the two kinds of key the
/// user holds. Each tab shows one kind, so selection and actions stay unambiguous.
struct KeysView: View {
    @Environment(AppModel.self) private var model

    @State private var identitiesToDelete: [AgeIdentity] = []
    @State private var signersToDelete: [SigningKey] = []
    @State private var isDeleteConfirmationPresented = false
    @AppStorage(PreferenceKeys.requireAuthToDelete) private var requireAuthToDelete = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Category", selection: $model.keyCategory) {
                ForEach(AppModel.KeyCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch model.keyCategory {
            case .encryption: encryptionKeys
            case .signing: signingKeys
            }
        }
        .navigationTitle("Keys")
        .toolbar { toolbar }
        // Switching tabs clears the selection so a stale id from the other kind
        // can't linger against the shared selection set.
        .onChange(of: model.keyCategory) { model.selectedKeyIDs = [] }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(deleteCount == 1 ? "Delete Key" : "Delete \(deleteCount) Keys",
                   role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteCount == 1
                 ? "This can’t be undone. Export the key first if you might need it again."
                 : "This can’t be undone. Export the keys first if you might need them again.")
        }
    }

    // MARK: Encryption keys

    @ViewBuilder private var encryptionKeys: some View {
        @Bindable var model = model
        if model.identities.isEmpty {
            ContentUnavailableView {
                Label("No Encryption Keys", systemImage: "key")
            } description: {
                Text("Generate an age keypair to start encrypting and decrypting. Secure Enclave keys never leave this Mac.")
            } actions: {
                Button("Generate age Keypair…", systemImage: "plus") { model.showGenerateSheet = true }
                    .buttonStyle(.borderedProminent)
                Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
            }
        } else {
            VStack(spacing: 0) {
                List(selection: $model.selectedKeyIDs) {
                    ForEach(model.identities) { identity in
                        IdentityRow(identity: identity) { requestDelete(identities: [identity]) }
                            .tag(identity.id)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    encryptionMenu(for: model.identities.filter { ids.contains($0.id) })
                } primaryAction: { ids in
                    if ids.count == 1, let key = model.identities.first(where: { ids.contains($0.id) }) {
                        model.editingKey = key
                    }
                }
                .onCopyCommand {
                    guard !model.selectedKeys.isEmpty else { return [] }
                    return [NSItemProvider(object: model.recipientsFile(for: model.selectedKeys) as NSString)]
                }
                .accessibilityLabel("age identities")
                Divider()
                Text("Keys live in your keychain. A local key stays on this Mac; a synced key shares to your other devices via iCloud Keychain; a Touch ID–protected key stays on this Mac and is sealed by the Secure Enclave, so its secret can’t be read at rest without authenticating. Secure Enclave keys never sync — they only work on the Mac that created them. You can export any key for backup, but an exported Secure Enclave key still only works on that Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    // MARK: Signing keys

    @ViewBuilder private var signingKeys: some View {
        @Bindable var model = model
        if model.signingKeys.isEmpty {
            ContentUnavailableView {
                Label("No Signing Keys", systemImage: "signature")
            } description: {
                Text("Generate a signing key to sign notes. Others check your signatures with its public verifier key.")
            } actions: {
                Button("Generate Signing Key…", systemImage: "plus") { model.showGenerateSigningKeySheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                List(selection: $model.selectedKeyIDs) {
                    ForEach(model.signingKeys) { signer in
                        SigningKeyRow(signer: signer) { requestDelete(signers: [signer]) }
                            .tag(signer.id)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    signingMenu(for: model.signingKeys.filter { ids.contains($0.id) })
                } primaryAction: { ids in
                    if ids.count == 1, let signer = model.signingKeys.first(where: { ids.contains($0.id) }) {
                        model.editingSigner = signer
                    }
                }
                .onCopyCommand {
                    let signers = model.selectedSigners
                    guard !signers.isEmpty else { return [] }
                    return [NSItemProvider(object: signers.map(\.verifierKeyEncoding).joined(separator: "\n") as NSString)]
                }
                .accessibilityLabel("signing identities")
                Divider()
                Text("A signing key signs notes; share its public verifier key so others can check your signatures. Like encryption keys it lives in your keychain — on this Mac, synced via iCloud Keychain, or Touch ID–protected. Its name is part of the key, so it can’t be renamed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            switch model.keyCategory {
            case .encryption:
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
                Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(identities: model.selectedKeys) }
                    .disabled(model.selectedKeys.isEmpty)
                Button("Import Identity…", systemImage: "square.and.arrow.down") { model.showImportSheet = true }
            case .signing:
                Button("Edit Key…", systemImage: "pencil") { model.editingSigner = model.singleSelectedSigner }
                    .disabled(model.singleSelectedSigner == nil)
                Button("Copy Verifier Keys", systemImage: "doc.on.doc") {
                    for signer in model.selectedSigners { model.copyVerifierKey(for: signer) }
                }
                .disabled(model.selectedSigners.isEmpty)
                Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(signers: model.selectedSigners) }
                    .disabled(model.selectedSigners.isEmpty)
            }
            Menu {
                Button("age Keypair…", systemImage: "lock") { model.showGenerateSheet = true }
                Button("Signing Key…", systemImage: "signature") { model.showGenerateSigningKeySheet = true }
            } label: {
                Label("Generate", systemImage: "plus")
            }
            .labelStyle(.titleAndIcon)
        }
    }

    // MARK: Context menus

    @ViewBuilder
    private func encryptionMenu(for keys: [AgeIdentity]) -> some View {
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
            Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(identities: keys) }
        }
    }

    @ViewBuilder
    private func signingMenu(for signers: [SigningKey]) -> some View {
        if !signers.isEmpty {
            let one = signers.count == 1
            Button("Copy \(one ? "Verifier Key" : "Verifier Keys")", systemImage: "doc.on.doc") {
                for signer in signers { model.copyVerifierKey(for: signer) }
            }
            if one {
                Button("Export Verifier Key…", systemImage: "square.and.arrow.up") {
                    model.exportVerifierKey(for: signers[0])
                }
                Divider()
                Button("Edit…", systemImage: "pencil") { model.editingSigner = signers.first }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(signers: signers) }
        }
    }

    // MARK: Deletion

    private var deleteCount: Int { identitiesToDelete.count + signersToDelete.count }

    private var deleteConfirmationTitle: String {
        if deleteCount == 1 {
            let name = identitiesToDelete.first?.displayName ?? signersToDelete.first?.displayName ?? ""
            return "Delete “\(name)”?"
        }
        return "Delete \(deleteCount) keys?"
    }

    private func requestDelete(identities: [AgeIdentity] = [], signers: [SigningKey] = []) {
        guard !identities.isEmpty || !signers.isEmpty else { return }
        identitiesToDelete = identities
        signersToDelete = signers
        isDeleteConfirmationPresented = true
    }

    /// Authenticate once when the preference asks for it, then delete every target.
    private func performDelete() {
        let identities = identitiesToDelete
        let signers = signersToDelete
        Task {
            if requireAuthToDelete {
                let reason = deleteCount == 1
                    ? String(localized: "Authenticate to delete this key.")
                    : String(localized: "Authenticate to delete \(deleteCount) keys.")
                guard await Authentication.authorize(reason: reason) else { return }
            }
            for identity in identities { model.delete(identity) }
            for signer in signers { model.deleteSigner(signer) }
        }
    }
}
