import SwiftUI
import AppKit
import Contacts
import AssuageCore

/// Pick a contact to add as recipients. Lists everyone who has a key we could encrypt
/// to, searchable; choosing one hands their keys back named after them. Gates on
/// Contacts access, offering to turn it on the same way the Contacts panel does.
struct ContactPickerSheet: View {
    @Environment(PeopleLibrary.self) private var people
    @Environment(\.dismiss) private var dismiss
    var onAdd: ([NamedRecipient]) -> Void

    @State private var search = ""
    @State private var selection: Person.ID?

    private var candidates: [Person] {
        people.people
            .filter(\.canEncrypt)
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !people.hasAccess {
                    accessGate
                } else if people.people.isEmpty, people.isLoading {
                    ProgressView("Loading contacts…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    empty
                } else {
                    List(candidates, selection: $selection) { person in
                        HStack(spacing: 8) {
                            Label(person.name.isEmpty ? "Unnamed contact" : person.name,
                                  systemImage: "person.crop.circle.fill")
                            Spacer()
                            Text("^[\(person.recipients.count) key](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add a Contact")
            .searchable(text: $search, prompt: "Search contacts")
            // Drop a selection a narrowed search has hidden, so Add can't take it.
            .onChange(of: candidates) {
                if let id = selection, !candidates.contains(where: { $0.id == id }) {
                    selection = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(selection == nil)
                }
            }
        }
        .frame(width: 440, height: 480)
        .task {
            if people.hasAccess, people.people.isEmpty { await people.load() }
        }
    }

    @ViewBuilder private var empty: some View {
        if !search.isEmpty {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView("No contacts with keys", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("Add a public key to a contact in the Contacts panel first, then they’ll show up here."))
        }
    }

    private var accessGate: some View {
        ContentUnavailableView {
            Label("Encrypt to people by name", systemImage: "person.2")
        } description: {
            Text("\(AppInfo.name) can read the public keys saved on your contacts, so you can add them as recipients by name.")
        } actions: {
            if people.authorization == .notDetermined {
                Button("Allow Access to Contacts") {
                    Task { await people.requestAccessAndLoad() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") { openContactsPrivacySettings() }
            }
        }
    }

    private func add() {
        guard let id = selection, let person = people.people.first(where: { $0.id == id }) else { return }
        onAdd(person.recipients.map { NamedRecipient(recipient: $0, name: person.name, contactID: person.id) })
        dismiss()
    }

    private func openContactsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }
}
