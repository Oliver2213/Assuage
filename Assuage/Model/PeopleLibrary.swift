import Foundation
import Contacts
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
        }
        await load()
    }

    /// Re-read all contacts if we have access. Fetching is I/O, so it runs off the
    /// main actor; a fresh `CNContactStore` is created there since it isn't Sendable.
    func load() async {
        authorization = CNContactStore.authorizationStatus(for: .contacts)
        guard hasAccess else { people = []; return }
        isLoading = true
        loadError = nil
        do {
            people = try await Task.detached { try PeopleLibrary.fetchAll() }.value
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
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
