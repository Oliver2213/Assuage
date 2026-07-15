import SwiftUI
import AppKit
import Contacts
import AssuageCore

/// The "Contacts and other recipients" panel: a filtered, searchable view over the
/// people you can encrypt to or verify notes from, read from Contacts. Read-only for
/// now — adding keys to a contact and encrypting to people come in later commits.
struct PeopleView: View {
    @Environment(PeopleLibrary.self) private var people
    @State private var filter: PeopleFilter = .withKeys
    @State private var search = ""
    @State private var editingPerson: Person?

    var body: some View {
        content
            .navigationTitle("Contacts and other recipients")
            .task {
                if people.hasAccess, people.people.isEmpty { await people.load() }
            }
            .sheet(item: $editingPerson, content: EditPersonSheet.init)
    }

    @ViewBuilder private var content: some View {
        if people.hasAccess {
            authorized
        } else if people.authorization == .notDetermined {
            accessPrompt
        } else {
            accessDenied
        }
    }

    // MARK: Authorized

    private var filtered: [Person] {
        people.people
            .filter(filter.matches)
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    @ViewBuilder private var authorized: some View {
        Group {
            if people.people.isEmpty, people.isLoading {
                ProgressView("Loading contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyResults
            } else {
                List {
                    ForEach(filtered) { person in
                        PersonRow(person: person)
                            .contextMenu { menu(for: person) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search contacts")
        .toolbar {
            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(PeopleFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
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
