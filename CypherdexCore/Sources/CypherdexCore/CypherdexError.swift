import Foundation

/// Errors surfaced by CypherdexCore.
///
/// Kept small and `Equatable` so both the UI and tests can pattern-match on them.
public enum CypherdexError: Error, Sendable, Equatable {
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
    /// The input was not a well-formed age file (bad armor, truncated header, …).
    case invalidAgeFile
    /// An underlying stream read/write failed.
    case ioFailure
    /// A Secure Enclave operation was requested on a Mac without one.
    case secureEnclaveUnavailable
    /// A capability that is planned but not built in this phase was requested.
    case featureNotYetImplemented(String)
}

extension CypherdexError: LocalizedError {
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
            return "This doesn\u{2019}t look like a valid age file."
        case .ioFailure:
            return "A read or write operation failed."
        case .secureEnclaveUnavailable:
            return "This Mac doesn\u{2019}t have a Secure Enclave."
        case .featureNotYetImplemented(let what):
            return "\(what) isn\u{2019}t available yet."
        }
    }
}
