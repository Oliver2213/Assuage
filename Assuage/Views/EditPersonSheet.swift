import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AssuageCore

/// Edit the public keys Assuage keeps on a person's contact card. Name and emails
/// come from Contacts and are read-only here (edit those in Contacts); only the age /
/// SSH / verifier keys are ours to add or remove. Changes are written on Save — never
/// deleting the contact or touching any other field.
struct EditPersonSheet: View {
    @Environment(PeopleLibrary.self) private var people
    @Environment(\.dismiss) private var dismiss

    let person: Person

    @State private var recipients: [AgeRecipient]
    @State private var verifierKeys: [VerifierKey]
    @State private var parseError: String?
    @State private var showFileImporter = false
    @State private var adding: AddKeySheet.Kind?
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    init(person: Person) {
        self.person = person
        _recipients = State(initialValue: person.recipients)
        _verifierKeys = State(initialValue: person.verifierKeys)
    }

    private var hasChanges: Bool {
        Set(recipients.map(\.id)) != Set(person.recipients.map(\.id))
            || Set(verifierKeys) != Set(person.verifierKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(person.name.isEmpty ? "Edit recipient" : "Keys for \(person.name)")
                .font(.title2.bold())

            Form {
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
                            Button(kind.menuTitle) { adding = kind }
                        }
                        Divider()
                        Button("From File…", systemImage: "doc.badge.plus") { showFileImporter = true }
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
            .formStyle(.grouped)

            Text("Saving writes these keys to \(person.name.isEmpty ? "this contact" : person.name)’s contact card. Assuage only changes its own key fields, and never deletes a contact.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isSaving)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || isSaving)
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
        .sheet(item: $adding) { kind in
            AddKeySheet(kind: kind) { append($0) }
        }
    }

    private func keyRow(type: String, remove: @escaping () -> Void, @ViewBuilder key: () -> some View) -> some View {
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

    private func typeLabel(for recipient: AgeRecipient) -> String {
        switch recipient.kind {
        case .sshEd25519: "SSH"
        case .postQuantum, .postQuantumHardware: "Age · PQ"
        default: "Age"
        }
    }

    // MARK: Actions

    /// Append a parsed key if we don't already hold it; returns whether it was new.
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

    /// Add every age / SSH recipient and verifier key found in a file (e.g. a
    /// recipients file or a `.pub`), skipping comments and duplicates.
    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
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
                try await people.updateKeys(for: person, recipients: recipients, verifierKeys: verifierKeys)
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
