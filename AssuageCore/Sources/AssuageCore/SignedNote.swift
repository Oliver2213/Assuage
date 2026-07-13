import Foundation

/// A note in the C2SP signed-note format (`c2sp.org/signed-note`): a UTF-8 text
/// ending in a newline, followed by a blank line, followed by one or more signature
/// lines of the form `— <name> <base64(keyID ‖ signature)>`.
///
/// Every signer signs the *text only* — never the other signatures — so adding a
/// signature never changes what earlier signers attested to. The text is held
/// separately from the signatures (not as raw `— …` lines in an editor), so it can
/// be edited and re-signed cleanly.
public struct SignedNote: Sendable, Hashable {
    /// The note body. Always ends in a single newline (one is appended if missing);
    /// this is the exact byte sequence that signatures cover.
    public private(set) var text: String
    /// The signatures currently attached, in order.
    public private(set) var signatures: [Signature]

    /// The em dash + space that begins every signature line (U+2014, U+0020).
    private static let signaturePrefix = "\u{2014} "
    /// The blank line separating the text from the signature block.
    private static let separator = "\n\n"

    /// A single signature line: a signer name and the raw bytes it carries (the
    /// 4-byte key ID followed by the Ed25519 signature). The name is the signer's
    /// self-asserted identity; trust comes only from verifying against a known key.
    public struct Signature: Sendable, Hashable, Identifiable {
        public let name: String
        /// key ID (4 bytes) ‖ Ed25519 signature (64 bytes).
        public let bytes: Data
        public var id: String { bytes.base64EncodedString() }

        /// The 4-byte key ID prefix, naming which key should verify this signature.
        public var keyIDBytes: [UInt8] { Array(bytes.prefix(4)) }
        public var keyIDHex: String { keyIDBytes.map { String(format: "%02x", $0) }.joined() }
        /// The raw 64-byte Ed25519 signature, without the key-ID prefix.
        public var signature: Data { bytes.dropFirst(4) }

        init(name: String, bytes: Data) {
            self.name = name
            self.bytes = bytes
        }
    }

    /// Start a note from plain text, with no signatures yet. A trailing newline is
    /// added if absent (the only normalization — nothing else is touched), so the
    /// note is spec-valid once signed.
    public init(text: String) {
        self.text = text.hasSuffix("\n") ? text : text + "\n"
        self.signatures = []
    }

    /// Parse a pasted note. If it has a well-formed signature block, the text and
    /// signatures are split apart; otherwise the whole input is treated as unsigned
    /// text (so ordinary multi-paragraph prose, which contains blank lines, isn't
    /// mistaken for a signature block).
    public init(parsing raw: String) {
        guard let separatorRange = raw.range(of: Self.separator, options: .backwards),
              let signatures = Self.parseSignatureBlock(String(raw[separatorRange.upperBound...])),
              !signatures.isEmpty
        else {
            self.text = raw.hasSuffix("\n") ? raw : raw + "\n"
            self.signatures = []
            return
        }
        // Text keeps the first of the two separator newlines as its own terminator.
        self.text = String(raw[..<raw.index(after: separatorRange.lowerBound)])
        self.signatures = signatures
    }

    /// Parse the block after the separator into signatures, or `nil` if any line
    /// isn't a valid `— <name> <base64>` signature line (meaning this wasn't a
    /// signature block at all).
    private static func parseSignatureBlock(_ block: String) -> [Signature]? {
        // A real block ends in a newline; drop it, then require every line to parse.
        guard block.hasSuffix("\n") else { return nil }
        let lines = block.dropLast().components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }
        var signatures: [Signature] = []
        for line in lines {
            guard line.hasPrefix(signaturePrefix) else { return nil }
            let rest = line.dropFirst(signaturePrefix.count)
            guard let space = rest.firstIndex(of: " ") else { return nil }
            let name = String(rest[..<space])
            let base64 = String(rest[rest.index(after: space)...])
            guard (try? VerifierKey.validate(name: name)) != nil,
                  let bytes = Data(base64Encoded: base64), bytes.count > 4
            else { return nil }
            signatures.append(Signature(name: name, bytes: bytes))
        }
        return signatures
    }

    /// The full serialized note: `text` + blank line + one line per signature. With
    /// no signatures this is just the text (not yet a valid signed note).
    public var serialized: String {
        guard !signatures.isEmpty else { return text }
        let block = signatures
            .map { "\(Self.signaturePrefix)\($0.name) \($0.bytes.base64EncodedString())" }
            .joined(separator: "\n")
        return text + "\n" + block + "\n"
    }

    /// Sign the note's text with `identity` and attach the signature.
    ///
    /// - Parameter keepingExisting: when `false`, existing signatures are dropped
    ///   first — use this when the text has changed, since their signatures no
    ///   longer cover it. Keeping is pure byte-preservation; we don't (and can't,
    ///   without their public keys) re-verify the retained signatures here.
    ///   A prior signature from the same key ID is always replaced.
    public mutating func sign(with identity: SigningIdentity, keepingExisting: Bool) throws {
        if !keepingExisting { signatures.removeAll() }
        let bytes = try identity.signatureBytes(for: Data(text.utf8))
        let signature = Signature(name: identity.name, bytes: bytes)
        signatures.removeAll { $0.keyIDBytes == signature.keyIDBytes && $0.name == signature.name }
        signatures.append(signature)
    }

    /// Check each signature against `trustedKeys`. A signature verifies if a trusted
    /// key with a matching ID validates it over the text; an ID match with a bad
    /// signature is `.invalid`; no ID match at all is `.unknownSigner`.
    public func verify(with trustedKeys: [VerifierKey]) -> [(signature: Signature, status: VerificationStatus)] {
        let message = Data(text.utf8)
        return signatures.map { signature in
            let candidates = trustedKeys.filter { $0.keyIDBytes == signature.keyIDBytes }
            guard !candidates.isEmpty else { return (signature, .unknownSigner) }
            if let match = candidates.first(where: { $0.isValidSignature(signature.signature, for: message) }) {
                return (signature, .verified(name: match.name))
            }
            return (signature, .invalid)
        }
    }

    /// The outcome of checking one signature against the trusted keys.
    public enum VerificationStatus: Sendable, Hashable {
        /// A trusted key validated the signature; `name` is that key's name.
        case verified(name: String)
        /// No trusted key has this signature's ID.
        case unknownSigner
        /// A trusted key's ID matched, but the signature didn't validate.
        case invalid
    }
}
