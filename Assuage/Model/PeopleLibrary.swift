import Foundation
import Contacts
import os
import AssuageCore

/// The people the user can encrypt to or verify notes from — a live view over the
/// system Contacts database. Shared across every window via a single instance, like
/// `KeyLibrary`.
///
/// Assuage keeps no parallel copy of this data: public keys, emails, and forge links
/// are read from (and written back to) contact cards. We only read the fields we
/// need, and only when the user has granted access.
@MainActor
@Observable
final class PeopleLibrary {
    /// Everyone loaded from Contacts. Empty until access is granted and a load runs.
    private(set) var people: [Person] = []
    /// The current Contacts authorization, kept in sync so the UI can gate itself.
    private(set) var authorization: CNAuthorizationStatus
    private(set) var isLoading = false
    private(set) var loadError: String?

    init() {
        authorization = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Whether we can read contacts right now. Full access on macOS; on iOS this
    /// also accepts the limited-access grant (which macOS doesn't offer).
    var hasAccess: Bool {
        if authorization == .authorized { return true }
        #if os(iOS)
        if #available(iOS 18.0, *) { return authorization == .limited }
        #endif
        return false
    }

    /// Prompt for access if undetermined, then load. Safe to call when already
    /// authorized (it just loads). The system remembers the decision, so a second
    /// call after a denial won't prompt again.
    func requestAccessAndLoad() async {
        if authorization == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            authorization = CNContactStore.authorizationStatus(for: .contacts)
            Log.contacts.notice("Contacts access request resolved to status \(self.authorization.rawValue)")
        }
        await load()
    }

    /// Re-read all contacts if we have access. Fetching is I/O, so it runs off the
    /// main actor; a fresh `CNContactStore` is created there since it isn't Sendable.
    func load() async {
        authorization = CNContactStore.authorizationStatus(for: .contacts)
        loadError = nil
        guard hasAccess else { people = []; return }
        isLoading = true
        do {
            people = try await Task.detached { try PeopleLibrary.fetchAll() }.value
            Log.contacts.info("Loaded \(self.people.count) contact(s)")
        } catch {
            loadError = error.localizedDescription
            Log.contacts.error("Loading contacts failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    /// An error writing back to a contact.
    enum WriteError: LocalizedError {
        case notAContact
        var errorDescription: String? {
            switch self {
            case .notAContact: "This recipient isn’t backed by a contact, so there’s nothing to save to."
            }
        }
    }

    /// Write the given public keys onto a contact, replacing whatever key fields we'd
    /// previously stored while leaving every other field — and the contact itself —
    /// untouched. Only our own URL entries are rewritten; the update is tagged with a
    /// transaction author and never deletes anything.
    func updateKeys(for person: Person, recipients: [AgeRecipient], verifierKeys: [VerifierKey]) async throws {
        guard case .contact(let identifier) = person.source else { throw WriteError.notAContact }
        let recipientCount = recipients.count
        let verifierCount = verifierKeys.count
        let author = AppInfo.name   // read on the main actor; capture the string for the write
        Log.contacts.notice("Saving keys to contact \(identifier, privacy: .private): \(recipientCount) recipient(s), \(verifierCount) verifier key(s)")
        do {
            try await Task.detached {
                let store = CNContactStore()
                // Fetch only urlAddresses: saving a partially-fetched contact leaves the
                // unfetched fields (name/email/phone/…) untouched. Only ever read/write
                // urlAddresses off this copy — touching an unfetched key would throw.
                let existing = try store.unifiedContact(
                    withIdentifier: identifier,
                    keysToFetch: [CNContactUrlAddressesKey as CNKeyDescriptor])
                guard let mutable = existing.mutableCopy() as? CNMutableContact else { return }

                // Keep every URL that isn't one of ours (by label or by decodable value),
                // then append the desired key set. Replacing wholesale keeps it idempotent.
                let others = mutable.urlAddresses.filter { labeled in
                    !ContactKeyField.isKeyLabel(labeled.label ?? "")
                        && ContactKeyField.decode(value: labeled.value as String) == nil
                }
                let entries = recipients.map(ContactKeyField.entry(for:))
                    + verifierKeys.map(ContactKeyField.entry(for:))
                let ours = entries.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) }
                mutable.urlAddresses = others + ours

                let request = CNSaveRequest()
                request.transactionAuthor = author
                request.update(mutable)
                try store.execute(request)
            }.value
        } catch {
            Log.contacts.error("Saving keys to a contact failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        Log.contacts.notice("Saved keys to contact \(identifier, privacy: .private)")
        await load()
    }

    /// Enumerate every contact, decoding each into a `Person`. Fetches only the keys
    /// we use (name, emails, URLs) — no photos, to keep a large address book light.
    private nonisolated static func fetchAll() throws -> [Person] {
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var people: [Person] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            people.append(Person(contact: contact))
        }
        return people
    }
}
