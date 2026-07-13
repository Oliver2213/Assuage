import Foundation
import AgeKit

/// Errors surfaced by AssuageCore.
///
/// Kept small and `Equatable` so both the UI and tests can pattern-match on them.
public enum AssuageError: Error, Sendable, Equatable {
    /// A string that was expected to be an age recipient could not be recognised.
    case unrecognizedRecipient(String)
    /// A string that was expected to be an age identity (secret key) could not be recognised.
    case unrecognizedIdentity(String)
    /// An encrypt call was made with an empty recipient list.
    case noRecipients
    /// A decrypt / check call was made with an empty identity list.
    case noIdentities
    /// A passphrase encrypt / decrypt call was made with an empty passphrase.
    case emptyPassphrase
    /// A passphrase decrypt failed: the passphrase is wrong, or the file isn't
    /// passphrase-encrypted.
    case incorrectPassphrase
    /// The input is not an age file at all — no armor header and no binary intro.
    case invalidAgeFile
    /// The input is recognizably age content (armored header or binary intro) but
    /// couldn't be read: damaged, incomplete, or a binary file pasted as text.
    case unreadableAgeFile
    /// None of the supplied identities is a recipient of the file (the list wasn't
    /// empty — see `noIdentities` for that).
    case noMatchingIdentity
    /// An underlying stream read/write failed.
    case ioFailure
    /// A Secure Enclave operation was requested on a Mac without one.
    case secureEnclaveUnavailable
    /// A capability that is planned but not built in this phase was requested.
    case featureNotYetImplemented(String)
    /// A recognizable but unsupported SSH key type (e.g. `ssh-rsa`, `ecdsa-…`).
    /// Only `ssh-ed25519` is supported.
    case unsupportedSSHKeyType(String)
    /// An SSH private key is passphrase-protected and no passphrase was supplied.
    case sshPassphraseRequired
    /// A note signer name broke the signed-note rules: empty, or containing a
    /// space or a `+`.
    case invalidSignerName(String)
    /// A string expected to be a signed note couldn't be parsed as one.
    case malformedSignedNote
}

extension AssuageError {
    /// Map an AgeKit `SSHKeyError` onto the app-facing error vocabulary, so
    /// callers never need to import AgeKit. `context` labels the input in the
    /// "unrecognized" fallback.
    init(sshKeyError error: SSHKeyError, context: String) {
        switch error {
        case .passphraseRequired: self = .sshPassphraseRequired
        case .incorrectPassphrase: self = .incorrectPassphrase
        case .unsupportedKeyType(let type): self = .unsupportedSSHKeyType(type)
        case .malformedPublicKey, .malformedPrivateKey, .unsupportedCipher, .unsupportedKDF:
            self = .unrecognizedIdentity(context)
        }
    }
}

extension AssuageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unrecognizedRecipient(let s):
            return "\u{201C}\(s)\u{201D} is not a recognised age recipient."
        case .unrecognizedIdentity(let s):
            return "\u{201C}\(s)\u{201D} is not a recognised age identity."
        case .noRecipients:
            return "Choose at least one recipient to encrypt to."
        case .noIdentities:
            return "Add at least one identity to decrypt with."
        case .emptyPassphrase:
            return "Enter a passphrase."
        case .incorrectPassphrase:
            return "The passphrase is incorrect, or this file isn\u{2019}t passphrase-encrypted."
        case .invalidAgeFile:
            return "This doesn\u{2019}t look like an age file. Paste armored age text, or drop the encrypted file."
        case .unreadableAgeFile:
            return "This looks like encrypted age file contents, but they couldn\u{2019}t be read \u{2014} the data may be incomplete or damaged. If you pasted a binary age file as text, copy it in armored form or drop the file instead."
        case .noMatchingIdentity:
            return "None of your selected identities can decrypt this file."
        case .ioFailure:
            return "A read or write operation failed."
        case .secureEnclaveUnavailable:
            return "This Mac doesn\u{2019}t have a Secure Enclave."
        case .featureNotYetImplemented(let what):
            return "\(what) isn\u{2019}t available yet."
        case .unsupportedSSHKeyType(let type):
            return "\(type) SSH keys aren\u{2019}t supported \u{2014} only ssh-ed25519."
        case .sshPassphraseRequired:
            return "This SSH key is passphrase-protected. Enter its passphrase to import it."
        case .invalidSignerName(let name):
            return "\u{201C}\(name)\u{201D} isn\u{2019}t a valid signer name \u{2014} it can\u{2019}t be empty or contain spaces or a \u{201C}+\u{201D}."
        case .malformedSignedNote:
            return "This doesn\u{2019}t look like a signed note."
        }
    }
}
