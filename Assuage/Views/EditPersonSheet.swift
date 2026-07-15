import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AssuageCore

/// Edit the public keys Assuage keeps on a person's contact card. Name and emails come
/// from Contacts and are read-only here (edit those in Contacts); the age / SSH /
/// verifier keys, forge links, and revoked-key lists are ours to manage. Changes are
/// written on Save — never deleting the contact or touching any other field.
///
/// Two kinds of URL do opposite jobs: a **forge link** is additive (fetch pulls in the
/// keys it serves), and a **revocation list** is subtractive (checking it removes any
/// key the contact has retired). A key is only ever removed by a revocation list or by
/// the user — a forge fetch never removes anything, so a key you add by hand stays.
struct EditPersonSheet: View {
    @Environment(PeopleLibrary.self) private var people
    @Environment(\.dismiss) private var dismiss

    let person: Person

    @State private var recipients: [AgeRecipient]
    @State private var verifierKeys: [VerifierKey]
    @State private var forgeLinks: [URL]
    @State private var revocationLists: [Person.RevocationList]
    @State private var parseError: String?
    @State private var syncMessage: String?
    /// The id of the URL currently being fetched/checked, so its row shows progress and
    /// the others disable. `nil` when idle.
    @State private var busyID: String?
    @State private var showFileImporter = false
    @State private var activeSheet: ActiveSheet?
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    /// The one sheet the editor can present: paste a key, fetch a forge, or add a
    /// revocation list. Modeled as one value so a single `.sheet(item:)` drives all.
    private enum ActiveSheet: Identifiable {
        case add(AddKeySheet.Kind)
        case forge
        case revocation(ContactRevocationField)
        var id: String {
            switch self {
            case .add(.age): "add-age"
            case .add(.ssh): "add-ssh"
            case .add(.verifier): "add-verifier"
            case .forge: "forge"
            case .revocation(let kind): "rev-\(kind.rawValue)"
            }
        }
    }

    init(person: Person) {
        self.person = person
        _recipients = State(initialValue: person.recipients)
        _verifierKeys = State(initialValue: person.verifierKeys)
        _forgeLinks = State(initialValue: person.forgeURLs)
        _revocationLists = State(initialValue: person.revocationLists)
    }

    private var hasChanges: Bool {
        Set(recipients) != Set(person.recipients)
            || Set(verifierKeys) != Set(person.verifierKeys)
            || Set(forgeLinks) != Set(person.forgeURLs)
            || Set(revocationLists) != Set(person.revocationLists)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(person.name.isEmpty ? "Edit recipient" : "Keys for \(person.name)")
                .font(.title2.bold())

            Form {
                identitySection
                keysSection
                forgeSection
                revocationSection
            }
            .formStyle(.grouped)

            if let syncMessage {
                Text(syncMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Saving writes these to \(person.name.isEmpty ? "this contact" : person.name)’s contact card. Assuage only changes its own fields, and never deletes a contact.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || isSaving || busyID != nil)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
        .alert("Couldn’t save", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.text, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { loadFile(url) }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add(let kind):
                AddKeySheet(kind: kind) { append($0) }
            case .forge:
                RecipientURLSheet { profile, recipients in addForge(profile: profile, recipients: recipients) }
            case .revocation(let kind):
                RevocationURLSheet(kind: kind, contactName: person.name) { addRevocationList(kind: kind, url: $0) }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var identitySection: some View {
        if case .contact = person.source {
            LabeledContent("Name") {
                HStack {
                    Text(person.name.isEmpty ? "Unnamed contact" : person.name)
                    Spacer()
                    Button("Edit in Contacts") { openInContacts() }
                        .controlSize(.small)
                }
            }
        }
        if !person.emails.isEmpty {
            LabeledContent("Email", value: person.emails.map(\.address).joined(separator: ", "))
        }
    }

    private var keysSection: some View {
        Section("Public keys") {
            if recipients.isEmpty, verifierKeys.isEmpty {
                Text("No keys yet. Use Add Key to add an age or SSH public key, or a note verifier key.")
                    .foregroundStyle(.secondary)
            }
            ForEach(recipients) { recipient in
                keyRow(type: typeLabel(for: recipient), remove: { remove(recipient) }) {
                    PublicKeyText(recipient: recipient)
                }
            }
            ForEach(verifierKeys) { verifier in
                keyRow(type: "Verifier", remove: { remove(verifier) }) {
                    PublicKeyText(key: verifier.encoded)
                }
            }
            Menu {
                ForEach(AddKeySheet.Kind.allCases) { kind in
                    Button(kind.menuTitle) { activeSheet = .add(kind) }
                }
                Divider()
                Button("From File…", systemImage: "doc.badge.plus") { showFileImporter = true }
                Button("Code Forge URL…", systemImage: "link") { activeSheet = .forge }
            } label: {
                Label("Add Key", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if let parseError {
                Text(parseError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var forgeSection: some View {
        if !forgeLinks.isEmpty {
            Section("Forge links") {
                ForEach(forgeLinks, id: \.self) { link in
                    urlRow(account: CodeForgeKeys.account(from: link), id: link.absoluteString,
                           action: "Fetch Keys") { await fetchForge(link) }
                }
                Text("Fetching adds the keys this profile serves now. It never removes a key — to drop a retired one, add a revocation list below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var revocationSection: some View {
        Section("Revocation lists") {
            ForEach(revocationLists) { list in
                urlRow(account: "\(list.kind.keyTypeName) · \(list.url.host() ?? list.url.absoluteString)",
                       id: list.id, action: "Check", remove: { remove(list) }) {
                    await checkRevocation(list)
                }
            }
            Menu {
                ForEach(ContactRevocationField.allCases, id: \.self) { kind in
                    Button("Revoked \(kind.keyTypeName) keys…") { activeSheet = .revocation(kind) }
                }
            } label: {
                Label("Add Revocation List", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Text("A revocation list is a URL where this contact publishes keys they’ve retired. Checking it removes any you hold — even keys you added yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Rows

    private func keyRow(type: String, remove: @escaping () -> Void,
                        @ViewBuilder key: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(type)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            key()
            Spacer()
            Button("Remove", systemImage: "minus.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    /// A URL row (forge link or revocation list): a label, a busy-aware action button,
    /// and an optional remove button.
    private func urlRow(account: String, id: String, action: LocalizedStringKey,
                        remove: (() -> Void)? = nil, run: @escaping () async -> Void) -> some View {
        HStack {
            Label(account, systemImage: "link").labelStyle(.titleAndIcon).lineLimit(1)
            Spacer()
            if busyID == id {
                ProgressView().controlSize(.small)
            } else {
                Button(action) { Task { await run() } }
                    .controlSize(.small)
                    .disabled(busyID != nil)
            }
            if let remove {
                Button("Remove", systemImage: "minus.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(busyID != nil)
            }
        }
    }

    private func typeLabel(for recipient: AgeRecipient) -> String {
        switch recipient.kind {
        case .sshEd25519: "SSH"
        case .postQuantum, .postQuantumHardware: "Age · PQ"
        default: "Age"
        }
    }

    // MARK: Add / remove keys

    /// Append a key if we don't already hold it; returns whether it was new.
    @discardableResult
    private func append(_ decoded: ContactKeyField.Decoded) -> Bool {
        parseError = nil
        switch decoded {
        case .recipient(let recipient):
            guard !recipients.contains(where: { $0.id == recipient.id }) else { return false }
            recipients.append(recipient)
            return true
        case .verifier(let verifier):
            guard !verifierKeys.contains(verifier) else { return false }
            verifierKeys.append(verifier)
            return true
        }
    }

    private func remove(_ recipient: AgeRecipient) { recipients.removeAll { $0.id == recipient.id } }
    private func remove(_ verifier: VerifierKey) { verifierKeys.removeAll { $0 == verifier } }
    private func remove(_ list: Person.RevocationList) { revocationLists.removeAll { $0.id == list.id } }

    // MARK: Forge links (additive)

    /// Keys fetched from a newly pasted forge URL: add them and keep the profile as a
    /// re-fetch anchor. Purely additive — nothing is removed.
    private func addForge(profile: String, recipients fetched: [NamedRecipient]) {
        let added = fetched.reduce(0) { append(.recipient($1.recipient)) ? $0 + 1 : $0 }
        guard let keysURL = CodeForgeKeys.keysURL(from: profile) else { return }
        let account = CodeForgeKeys.account(from: keysURL)
        if let url = URL(string: "https://\(account)"), !forgeLinks.contains(url) { forgeLinks.append(url) }
        syncMessage = String(localized: "Added \(account) — \(added) key(s).")
    }

    /// Re-fetch an existing forge link and add anything new it now serves.
    private func fetchForge(_ link: URL) async {
        busyID = link.absoluteString
        syncMessage = nil
        defer { busyID = nil }
        do {
            let fetched = try await CodeForgeKeys.fetch(fromProfile: link.absoluteString)
            let added = fetched.reduce(0) { append(.recipient($1.recipient)) ? $0 + 1 : $0 }
            syncMessage = String(localized: "Fetched \(CodeForgeKeys.account(from: link)) — \(added) added.")
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    // MARK: Revocation lists (subtractive)

    private func addRevocationList(kind: ContactRevocationField, url: URL) {
        let list = Person.RevocationList(kind: kind, url: url)
        guard !revocationLists.contains(list) else { return }
        revocationLists.append(list)
    }

    /// Fetch a revocation list and remove any key we hold that appears on it.
    private func checkRevocation(_ list: Person.RevocationList) async {
        busyID = list.id
        syncMessage = nil
        defer { busyID = nil }
        do {
            let revoked = try await CodeForgeKeys.fetchKeyList(from: list.url)
            let removed = applyRevocations(revoked)
            syncMessage = String(localized: "Checked \(list.kind.keyTypeName) revocations — \(removed) removed.")
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    /// Remove every held key that appears in a revoked-key list, whatever its origin.
    /// Returns how many were removed.
    private func applyRevocations(_ revoked: [ContactKeyField.Decoded]) -> Int {
        var removed = 0
        for decoded in revoked {
            switch decoded {
            case .recipient(let recipient) where recipients.contains(where: { $0.id == recipient.id }):
                recipients.removeAll { $0.id == recipient.id }
                removed += 1
            case .verifier(let verifier) where verifierKeys.contains(verifier):
                verifierKeys.removeAll { $0 == verifier }
                removed += 1
            default:
                break
            }
        }
        return removed
    }

    // MARK: File / save

    /// Add every age / SSH recipient and verifier key found in a file (e.g. a
    /// recipients file or a `.pub`), skipping comments and duplicates.
    private func loadFile(_ url: URL) {
        do {
            let text = try url.readingSecurityScopedText()
            var added = 0
            for line in text.split(whereSeparator: \.isNewline) {
                let entry = line.trimmingCharacters(in: .whitespaces)
                guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
                if let decoded = ContactKeyField.parse(entry), append(decoded) { added += 1 }
            }
            parseError = added == 0 ? String(localized: "No age, SSH, or verifier keys found in that file.") : nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await people.updateKeys(for: person, recipients: recipients, verifierKeys: verifierKeys,
                                            revocationLists: revocationLists, forgeLinks: forgeLinks)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
                isSaving = false
            }
        }
    }

    private func openInContacts() {
        if case .contact(let id) = person.source, let url = URL(string: "addressbook://\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
