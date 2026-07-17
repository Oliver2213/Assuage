import SwiftUI
import AppKit
import os
import AssuageCore

/// Decrypt one kind of input, chosen by `scope`: pasted age text (Text panel) or a
/// queue of `.age` files (Files panel). Identity/passphrase controls are shared.
struct DecryptView: View {
    let scope: ComposeScope
    @Environment(AppModel.self) private var model
    @Environment(PeopleLibrary.self) private var people
    @State private var viewModel = DecryptViewModel()
    /// Header info for the queued files, refreshed when the queue changes.
    @State private var fileInfos: [URL: AgeFileInfo] = [:]

    private var identities: [AgeIdentity] {
        model.identities.filter { model.decryptIdentityIDs.contains($0.id) }
    }

    /// Header info for the pasted text, when it parses as an age file.
    private var inputInfo: AgeFileInfo? {
        guard !model.decryptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? AgeFileInspector.inspect(Data(model.decryptInput.utf8))
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner(banner)

                if scope == .text {
                    MultilineTextField(
                        title: "Encrypted text",
                        placeholder: "-----BEGIN AGE ENCRYPTED FILE-----…",
                        text: $model.decryptInput,
                        font: .caption.monospaced()
                    )
                    if let inputInfo {
                        AgeFileInfoView(info: inputInfo,
                                        decryptability: decryptability(of: inputInfo),
                                        identifiedRecipients: identifiedRecipients(of: inputInfo))
                    }
                }

                Picker("Decrypt with", selection: $model.decryptMode) {
                    Text("Identities").tag(AppModel.CredentialMode.keys)
                    Text("Passphrase").tag(AppModel.CredentialMode.passphrase)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.decryptMode {
                case .keys:
                    if model.identities.isEmpty {
                        GroupBox("Try these identities") {
                            Text("No identities yet — generate or import one in the Keys tab.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                    } else {
                        IdentityCheckTable(identities: model.identities, selection: $model.decryptIdentityIDs, title: "Try these identities", showsPresence: true)
                    }
                case .passphrase:
                    GroupBox("Passphrase") {
                        PassphraseField(prompt: "Passphrase", text: $model.decryptPassphrase)
                            .padding(4)
                    }
                }

                if scope == .text {
                    HStack(spacing: 12) {
                        Button("Decrypt", systemImage: "lock.open", action: decrypt)
                            .buttonStyle(.borderedProminent)
                            .help("Decrypt (⌘Return)")
                            .disabled(model.decryptInput.isEmpty || !canDecrypt || viewModel.isRunning)
                        if model.decryptMode == .keys {
                            Button("Check", systemImage: "questionmark.circle", action: check)
                                .disabled(model.decryptInput.isEmpty || identities.isEmpty || viewModel.isRunning)
                        }
                        if viewModel.isRunning {
                            ProgressStrip(progress: viewModel.progress).frame(maxWidth: 260)
                        }
                        Spacer()
                    }
                }

                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: viewModel.statusIsGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(viewModel.statusIsGood ? .green : .orange)
                }

                if scope == .text, let output = viewModel.output {
                    CipherOutputView(title: "Decrypted", output: output, binarySaveName: "decrypted", sensitive: true)
                }

                if scope == .files {
                    QueuedFilesSection(
                        caption: "Writes each decrypted file next to the encrypted one.",
                        files: $model.queuedDecryptFiles,
                        runVerb: "Decrypt",
                        runIcon: "lock.open",
                        dropPrompt: "Drop files to decrypt",
                        dropIcon: "arrow.up.doc",
                        isRunEnabled: canDecrypt && !viewModel.isRunning,
                        onRun: decryptFiles
                    )

                    ForEach(model.queuedDecryptFiles, id: \.self) { url in
                        if let info = fileInfos[url] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                AgeFileInfoView(info: info,
                                                decryptability: decryptability(of: info),
                                                identifiedRecipients: identifiedRecipients(of: info))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            if model.decryptIdentityIDs.isEmpty { selectAllIdentities() }
            runAutoCheckIfNeeded()
            refreshFileInfos()
        }
        .task {
            // Best-effort: if Contacts access is already granted, make sure people are
            // loaded so recipients can be named. Never prompts — naming is a bonus.
            if people.hasAccess, people.people.isEmpty { await people.load() }
        }
        .onChange(of: model.queuedDecryptFiles) { refreshFileInfos() }
        .onChange(of: model.autoCheckRequested) { _, requested in
            if requested { runAutoCheckIfNeeded() }
        }
        .onChange(of: model.runComposeAction) { _, run in
            guard run, model.selection == scope.panel, model.operation == .decrypt else { return }
            model.runComposeAction = false
            runPrimaryAction()
        }
        .alert("Couldn’t decrypt", isPresented: $viewModel.isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var banner: LocalizedStringKey {
        scope == .text
            ? "**Decrypt text.** Paste armored age text and decrypt with your identities (or a passphrase). **Check** tells you whether one of your keys can open it, without decrypting."
            : "**Decrypt files.** Drop **.age** files to decrypt each next to the original. Also from **Services** and Finder."
    }

    private func runPrimaryAction() {
        switch scope {
        case .text: decrypt()
        case .files: decryptFiles()
        }
    }

    /// The header-only "can you open this?" verdict for an inspected file, or nil
    /// when there are no identities to judge against (keeps the row hidden on a
    /// fresh install). Uses only public key material — nothing is unlocked.
    private func decryptability(of info: AgeFileInfo) -> DecryptionCapability? {
        model.identities.isEmpty ? nil : info.decryptability(with: model.identities)
    }

    /// Put names to the file's recipients from public data only: a contact whose
    /// published key provably addresses the header (clickable — reveals the card),
    /// and any of your own keys that match (labeled "You"). Only the recipient types
    /// carrying a public tag can be named; anonymous X25519 recipients never appear
    /// here. A held key that's *also* on a contact card is shown as the contact, so
    /// the "You" rows are the keys you hold that aren't published to anyone.
    private func identifiedRecipients(of info: AgeFileInfo) -> [IdentifiedRecipient] {
        var results: [IdentifiedRecipient] = []
        var contactKeyIDs: Set<AgeRecipient.ID> = []

        // Contacts first (best-effort; only if access is already granted).
        if people.hasAccess {
            for person in people.people {
                guard case .contact(let contactID) = person.source else { continue }
                for recipient in person.recipients where info.addresses(recipient) {
                    contactKeyIDs.insert(recipient.id)
                    results.append(IdentifiedRecipient(
                        id: "contact:\(person.id):\(recipient.id)",
                        name: person.name,
                        detail: recipient.kind.recipientLabel,
                        systemImage: "person.crop.circle",
                        onSelect: { revealContact(contactID) }
                    ))
                }
            }
        }

        // Then your own matching keys that aren't already published on a card.
        for identity in model.identities where info.addresses(identity.recipient) {
            guard !contactKeyIDs.contains(identity.recipient.id) else { continue }
            let name = identity.label.isEmpty ? "You" : "You · \(identity.label)"
            results.append(IdentifiedRecipient(
                id: "you:\(identity.id)",
                name: name,
                detail: identity.recipient.kind.recipientLabel,
                systemImage: "person.crop.circle.badge.checkmark",
                onSelect: nil
            ))
        }

        if !results.isEmpty {
            Log.inspector.info("Named \(results.count) of the file's recipients from held keys/contacts")
        }
        return results
    }

    /// Open the given contact in the Contacts app — the same reveal used elsewhere.
    private func revealContact(_ identifier: String) {
        guard let url = URL(string: "addressbook://\(identifier)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Whether the current mode has what it needs to decrypt.
    private var canDecrypt: Bool {
        switch model.decryptMode {
        case .keys: return !identities.isEmpty
        case .passphrase: return !model.decryptPassphrase.isEmpty
        }
    }

    private func decrypt() {
        guard !model.decryptInput.isEmpty, canDecrypt, !viewModel.isRunning else { return }
        Task {
            switch model.decryptMode {
            case .keys:
                guard let identities = await hydratedIdentities() else { return }
                await viewModel.decrypt(model.decryptInput, with: identities)
            case .passphrase:
                if await viewModel.decrypt(model.decryptInput, passphrase: model.decryptPassphrase) {
                    model.decryptPassphrase = ""
                }
            }
        }
    }

    private func check() {
        Task {
            guard let identities = await hydratedIdentities() else { return }
            await viewModel.check(model.decryptInput, with: identities)
        }
    }

    private func decryptFiles() {
        let files = model.queuedDecryptFiles
        guard !files.isEmpty, canDecrypt, !viewModel.isRunning else { return }
        Task {
            switch model.decryptMode {
            case .keys:
                guard let identities = await hydratedIdentities() else { return }
                await viewModel.decryptFiles(files, with: identities)
            case .passphrase:
                if await viewModel.decryptFiles(files, passphrase: model.decryptPassphrase) {
                    model.decryptPassphrase = ""
                }
            }
            model.queuedDecryptFiles.removeAll()
        }
    }

    /// Unlock the selected identities' secrets (one Touch ID prompt covers any
    /// protected keys). Returns nil if the user cancels, so the caller aborts.
    private func hydratedIdentities() async -> [AgeIdentity]? {
        try? await model.hydratedSecrets(for: identities)
    }

    private func runAutoCheckIfNeeded() {
        guard model.autoCheckRequested, model.decryptMode == .keys else { return }
        model.autoCheckRequested = false
        if model.decryptIdentityIDs.isEmpty { selectAllIdentities() }
        guard !model.decryptInput.isEmpty, !identities.isEmpty else { return }
        check()
    }

    private func selectAllIdentities() {
        model.decryptIdentityIDs = Set(model.identities.map(\.id))
    }

    /// Inspect each queued file's header (a cheap, mapped read) so its recipient
    /// types and size breakdown can be shown alongside the queue.
    private func refreshFileInfos() {
        var infos: [URL: AgeFileInfo] = [:]
        for url in model.queuedDecryptFiles {
            if let info = try? AgeFileInspector.inspect(contentsOf: url) { infos[url] = info }
        }
        fileInfos = infos
    }
}
