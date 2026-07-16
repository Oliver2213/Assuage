import SwiftUI
import UniformTypeIdentifiers
import AssuageCore

/// Chooses recipients: a titled checkbox table over the user's own keys, plus a
/// table of ad-hoc recipients added by pasting an `age1…` string, loading a
/// recipients file, or fetching a code-forge URL.
struct RecipientSelector: View {
    let identities: [AgeIdentity]
    @Binding var selectedIdentityIDs: Set<UUID>
    @Binding var extraRecipients: [NamedRecipient]
    @Binding var selectedExtraIDs: Set<String>

    @State private var field = ""
    @State private var parseError: String?
    @State private var showURLSheet = false
    @State private var showFileImporter = false
    @State private var showContactPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if identities.isEmpty && extraRecipients.isEmpty {
                Text("No recipients yet — add a public key below, or generate one in the Keys tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !identities.isEmpty {
                IdentityCheckTable(identities: identities, selection: $selectedIdentityIDs, title: "Choose identities")
            }

            if !extraRecipients.isEmpty {
                RecipientTable(recipients: $extraRecipients, selection: $selectedExtraIDs, title: "Extra recipients")
            }

            HStack {
                TextField("Add a recipient (age1…)", text: $field)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(field.trimmingCharacters(in: .whitespaces).isEmpty)
                Menu {
                    Button("Contact…", systemImage: "person.crop.circle") { showContactPicker = true }
                    Button("From File…", systemImage: "doc.badge.plus") { showFileImporter = true }
                    Button("Code Forge URL…", systemImage: "link") { showURLSheet = true }
                } label: {
                    Label("Add from…", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add recipients from a contact, a file, or a code-forge URL")
            }

            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showURLSheet) {
            RecipientURLSheet { _, recipients in addUnique(recipients) }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet(purpose: .recipients) { person in
                addUnique(person.recipients.map { NamedRecipient(recipient: $0, name: person.name, contactID: person.id) },
                          includingOwned: true)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.text, .plainText, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadRecipientsFile(url)
            }
        }
    }

    /// Add the single recipient typed into the field.
    private func add() {
        let raw = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        do {
            let recipient = try AgeRecipient(parsing: raw)
            addUnique([NamedRecipient(recipient: recipient, name: nil)])
            field = ""
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func loadRecipientsFile(_ url: URL) {
        do {
            let text = try url.readingSecurityScopedText()
            let loaded = NamedRecipient.parse(recipientsFile: text)
            guard !loaded.isEmpty else {
                parseError = String(localized: "No recipients found in that file.")
                return
            }
            addUnique(loaded)
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    /// Append recipients not already in the list. When adding from a paste or a forge
    /// URL we also skip the user's own keys (already offered in the table above); when
    /// they explicitly pick a contact we add every key that contact publishes, own or not.
    private func addUnique(_ recipients: [NamedRecipient], includingOwned: Bool = false) {
        let owned = includingOwned ? Set<AgeRecipient>() : Set(identities.map(\.recipient))
        for item in recipients
        where !owned.contains(item.recipient) && !extraRecipients.contains(where: { $0.recipient == item.recipient }) {
            extraRecipients.append(item)
            selectedExtraIDs.insert(item.id)
        }
    }
}
