import SwiftUI
import AppKit
import Contacts
import AssuageCore

/// The "Contacts and other recipients" panel: a searchable, filterable table of the
/// people you can encrypt to or verify notes from, read from Contacts, with an
/// inspector detailing the selected contact. A table (not a nested split view) keeps
/// this as page content — the app's only sidebar stays the tab sidebar.
struct PeopleView: View {
    @Environment(PeopleLibrary.self) private var people
    @State private var filter: PeopleFilter = .withKeys
    @State private var search = ""
    @State private var selection: Set<Person.ID> = []
    @State private var showInspector = true
    @State private var editingPerson: Person?

    var body: some View {
        Group {
            if people.hasAccess {
                table
            } else if people.authorization == .notDetermined {
                accessPrompt
            } else {
                accessDenied
            }
        }
        .navigationTitle("Contacts and other recipients")
        .task {
            if people.hasAccess, people.people.isEmpty { await people.load() }
        }
        .sheet(item: $editingPerson, content: EditPersonSheet.init)
    }

    // MARK: Table

    private var filtered: [Person] {
        people.people
            .filter(filter.matches)
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    private var selectedPerson: Person? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return filtered.first { $0.id == id }
    }

    @ViewBuilder private var table: some View {
        Group {
            if people.people.isEmpty, people.isLoading {
                ProgressView("Loading contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyResults
            } else {
                Table(filtered, selection: $selection) {
                    TableColumn("Name") { person in
                        Label(person.name.isEmpty ? "Unnamed contact" : person.name,
                              systemImage: "person.crop.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    TableColumn("Email") { person in
                        Text(person.emails.first?.address ?? "—").foregroundStyle(.secondary)
                    }
                    TableColumn("Keys") { person in
                        capabilityTags(for: person)
                    }
                }
                .contextMenu(forSelectionType: Person.ID.self) { ids in
                    if let person = person(for: ids) { menu(for: person) }
                } primaryAction: { ids in
                    if let person = person(for: ids) { editingPerson = person }
                }
            }
        }
        .searchable(text: $search, prompt: "Search contacts")
        // Drop any selection a filter/search change has hidden.
        .onChange(of: filtered) { selection.formIntersection(filtered.map(\.id)) }
        .toolbar {
            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(PeopleFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        .inspector(isPresented: $showInspector) {
            if let selectedPerson {
                PersonDetail(person: selectedPerson) { editingPerson = selectedPerson }
            } else {
                ContentUnavailableView("No Contact Selected", systemImage: "person.crop.circle",
                                       description: Text("Select a contact to see their keys and what you can do with them."))
            }
        }
    }

    /// Capability chips for the Keys column: a plain age key, post-quantum, SSH, a note
    /// verifier key, and a forge link we could fetch keys from.
    @ViewBuilder private func capabilityTags(for person: Person) -> some View {
        let tags = [
            person.ageRecipients.contains { !$0.isPostQuantum } ? "Age" : nil,
            person.canEncryptPostQuantum ? "PQ" : nil,
            person.sshRecipients.isEmpty ? nil : "SSH",
            person.canVerifyNotes ? "Verifier" : nil,
            person.forgeURLs.isEmpty ? nil : "Link",
        ].compactMap { $0 }
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .foregroundStyle(.secondary)
    }

    private func person(for ids: Set<Person.ID>) -> Person? {
        ids.first.flatMap { id in people.people.first { $0.id == id } }
    }

    @ViewBuilder private var emptyResults: some View {
        if !search.isEmpty {
            ContentUnavailableView.search
        } else if filter == .withKeys {
            ContentUnavailableView {
                Label("No recipients with keys yet", systemImage: "person.2")
            } description: {
                Text("People appear here once their contact has an age or SSH public key — added by you, or fetched from a profile link like GitHub or Codeberg. Choose “All contacts” in the filter to see everyone.")
            }
        } else {
            ContentUnavailableView("No matches", systemImage: "person.2",
                                   description: Text("No contacts match this filter."))
        }
    }

    @ViewBuilder private func menu(for person: Person) -> some View {
        Button("Edit Keys…", systemImage: "pencil") { editingPerson = person }
        Button("Copy Public Keys", systemImage: "doc.on.doc") { copyPublicKeys(person) }
            .disabled(person.recipients.isEmpty)
        if case .contact(let id) = person.source {
            Divider()
            Button("Show in Contacts", systemImage: "person.crop.circle") { openInContacts(id) }
        }
    }

    // MARK: Access gates

    private var accessPrompt: some View {
        ContentUnavailableView {
            Label("Encrypt to people by name", systemImage: "person.2")
        } description: {
            Text("Assuage can read the public keys and forge links saved on your contacts, so you can encrypt to people by name and verify their signed notes. It only adds keys when you ask, and never deletes a contact.")
        } actions: {
            Button("Allow Access to Contacts") {
                Task { await people.requestAccessAndLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Contacts access is off", systemImage: "person.2.slash")
        } description: {
            Text("Assuage needs Contacts access to encrypt to people by name. Turn it on in System Settings, under Privacy & Security ▸ Contacts.")
        } actions: {
            Button("Open System Settings") { openContactsPrivacySettings() }
        }
    }

    // MARK: Actions

    private func copyPublicKeys(_ person: Person) {
        Pasteboard.copy(person.recipients.map(\.encoding).joined(separator: "\n"), sensitive: false)
    }

    private func openInContacts(_ identifier: String) {
        if let url = URL(string: "addressbook://\(identifier)") { NSWorkspace.shared.open(url) }
    }

    private func openContactsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }
}
