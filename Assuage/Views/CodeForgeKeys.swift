import Foundation
import AssuageCore

/// Fetches a code-forge account's public keys from its unofficial `.keys` page
/// (GitHub, Codeberg, SourceHut, …) and parses them into named recipients.
enum CodeForgeKeys {
    enum FetchError: LocalizedError {
        case invalidURL
        case httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return String(localized: "That doesn’t look like a valid URL.")
            case .httpStatus(let code): return String(localized: "The server returned an error (HTTP \(code)).")
            }
        }
    }

    /// Turn a pasted profile URL into its `.keys` URL: assume https when no scheme
    /// is given, and append `.keys` unless it's already there.
    static func keysURL(from input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix(".keys") { s += ".keys" }
        return URL(string: s)
    }

    /// The account shown in key names: the `.keys` URL without scheme or suffix,
    /// e.g. `github.com/alice`.
    static func account(from keysURL: URL) -> String {
        var s = keysURL.absoluteString
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if s.hasSuffix(".keys") { s = String(s.dropLast(5)) }
        return s
    }

    /// Fetch a key list from an *exact* URL (no `.keys` transform) and parse each line
    /// as an age / SSH recipient or a note verifier key. Used for a contact's revoked-
    /// key list, whose URL is whatever the contact published. Unparseable lines skipped.
    static func fetchKeyList(from url: URL) async throws -> [ContactKeyField.Decoded] {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { ContactKeyField.parse(String($0)) }
    }

    /// Fetch the `.keys` page and parse each line as an age or SSH recipient,
    /// naming them "key N from <account>". Unparseable lines are skipped.
    static func fetch(fromProfile input: String) async throws -> [NamedRecipient] {
        guard let url = keysURL(from: input) else { throw FetchError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        let account = account(from: url)
        var result: [NamedRecipient] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let recipient = try? AgeRecipient(parsing: trimmed) else { continue }
            result.append(NamedRecipient(recipient: recipient, name: "key \(result.count + 1) from \(account)"))
        }
        return result
    }
}
