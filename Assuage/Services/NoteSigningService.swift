import Foundation
import LocalAuthentication
import AssuageCore

/// Signs text as a C2SP signed note for the system "Sign Note" Service, entirely
/// synchronously and without the app's UI. It reads the note signing keys straight
/// from the keychain (the same store `KeyLibrary` uses) so the Service can produce
/// a signed note and hand it back on the pasteboard before returning — which is how
/// a Service replaces the selected text in place.
///
/// A Touch ID / passcode–protected key prompts inline here (the keychain read
/// presents the system authentication sheet and blocks until it's answered), so a
/// protected key still signs without opening the app.
enum NoteSigningService {
    /// Sign `text` with the keys chosen by the `DefaultSigningIdentities` preference.
    ///
    /// - Returns: the serialized signed note.
    /// - Throws: `AssuageError.noIdentities` if there are no signing keys, or a
    ///   keychain/auth error if a protected key can't be read.
    static func sign(_ text: String) throws -> String {
        let store = KeyLibrary.makeSignerStore()
        let chosen = DefaultSigningIdentities.current.select(from: store.loadAll())
        guard !chosen.isEmpty else { throw AssuageError.noIdentities }

        // One context for the whole batch, so a set of protected keys prompts once.
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration

        var note = SignedNote(text: text)
        for key in chosen {
            let seed = try store.secret(for: key, context: context)
            try note.sign(with: key.withSeed(seed).signingIdentity(), keepingExisting: true)
        }
        return note.serialized
    }
}
