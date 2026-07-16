import SwiftUI
import AppKit
import Contacts
import AssuageCore

/// Pick a contact for a task that draws on their saved keys — either to encrypt to
/// them or to trust their signed notes. Lists everyone who has the kind of key the
/// task needs, searchable; choosing one hands the whole card back so the caller pulls
/// what it needs by card, not by name. Gates on Contacts access, offering to turn it
/// on the same way the Contacts panel does.
struct ContactPickerSheet: View {
    /// What we're picking a contact for — drives the candidate filter and the copy.
    enum Purpose {
        case recipients   // encrypt to them: only contacts that already have a key
        case noteSigner   // give one a note signing key: every contact, since the
                          // whole point is to reach one that doesn't have one yet
    }

    @Environment(PeopleLibrary.self) private var people
    @Environment(\.dismiss) private var dismiss
    var purpose: Purpose = .recipients
    var onAdd: (Person) -> Void

    @State private var search = ""
    @State private var selection: Person.ID?

    private var candidates: [Person] {
        people.people
            .filter(includes)
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
                            Text(keyCountLabel(person))
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

    /// Whether a contact belongs in the list for this pick. Recipients must already
    /// have a key to encrypt to; for a note signing key we show everyone, so you can
    /// pick a contact that has none yet.
    private func includes(_ person: Person) -> Bool {
        switch purpose {
        case .recipients: person.canEncrypt
        case .noteSigner: true
        }
    }

    /// A short count of the relevant keys, for the row's trailing label. For note
    /// signing this includes zero, so you can see who still needs a key.
    private func keyCountLabel(_ person: Person) -> LocalizedStringKey {
        switch purpose {
        case .recipients: "^[\(person.recipients.count) key](inflect: true)"
        case .noteSigner: "^[\(person.verifierKeys.count) signer key](inflect: true)"
        }
    }

    @ViewBuilder private var empty: some View {
        if !search.isEmpty {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(emptyTitle, systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text(emptyMessage))
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch purpose {
        case .recipients: "No contacts with keys"
        case .noteSigner: "No contacts"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch purpose {
        case .recipients: "Add a public key to a contact in the Contacts panel first, then they’ll show up here."
        case .noteSigner: "Add someone to your Contacts first, then choose them here to save their note signing key."
        }
    }

    private var accessGate: some View {
        ContentUnavailableView {
            Label(gateTitle, systemImage: "person.2")
        } description: {
            Text(gateMessage)
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

    private var gateTitle: LocalizedStringKey {
        switch purpose {
        case .recipients: "Encrypt to people by name"
        case .noteSigner: "Verify notes from people you know"
        }
    }

    private var gateMessage: LocalizedStringKey {
        switch purpose {
        case .recipients: "\(AppInfo.name) can read the public keys saved on your contacts, so you can add them as recipients by name."
        case .noteSigner: "\(AppInfo.name) saves note signing keys onto your contacts, so a note signed by one shows as verified instead of an unknown signer."
        }
    }

    private func add() {
        guard let id = selection, let person = people.people.first(where: { $0.id == id }) else { return }
        onAdd(person)
        dismiss()
    }

    private func openContactsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }
}
