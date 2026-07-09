import Foundation

/// A read-only summary of an age file's header — the same information the
/// `age-inspect` tool reports — obtained without decrypting the payload or
/// holding any key.
///
/// Only the cleartext header (the recipient stanzas) is parsed, so this is safe
/// to run on an untrusted file and cheap enough for Finder / Quick Look. The
/// byte `sizes` breakdown additionally needs the payload to be present.
public struct AgeFileInfo: Sendable, Equatable {
    /// The only format version this parser accepts, and what a valid file's
    /// header intro line reads.
    public static let currentVersion = "age-encryption.org/v1"

    /// Whether the file uses ASCII armor (PEM) rather than the binary format.
    public let isArmored: Bool

    /// The format version from the header intro line.
    public let version: String

    /// Every recipient stanza type in header order, verbatim — including the
    /// random `*-grease` stanza age/rage add to every header for tamper-evidence.
    public let stanzaTypes: [String]

    /// The real recipients (grease excluded), each classified into a `Kind`.
    public let recipients: [Recipient]

    /// Whether the file is post-quantum secure, mirroring `age-inspect`: `.no`
    /// if any classical recipient is present, `.yes` if only post-quantum or
    /// passphrase stanzas are, `.unknown` if it can't tell.
    public let postQuantum: PostQuantum

    /// The file's byte breakdown, when the payload is present and well-formed.
    /// `nil` if only the header was available (e.g. a truncated Quick Look read)
    /// or the payload size doesn't validate as an age STREAM.
    public let sizes: Sizes?

    /// True when the file is locked by a passphrase — a single `scrypt` stanza —
    /// rather than by public-key recipients.
    public var isPassphrase: Bool {
        recipients.count == 1 && recipients[0].kind == .passphrase
    }

    public enum PostQuantum: String, Sendable, Equatable {
        case yes, no, unknown
    }

    /// One recipient stanza, classified. `id` is the header position so repeated
    /// types stay distinct in a list.
    public struct Recipient: Sendable, Equatable, Identifiable {
        public let id: Int
        /// The raw stanza type, e.g. `X25519`, `scrypt`, `ssh-ed25519`.
        public let type: String
        /// The stanza arguments after the type — public header data (e.g. the
        /// recipient key tag and the ephemeral share). Used by
        /// `decryptability(with:)` to match a file against held keys without
        /// reading any secret. Anonymous X25519 stanzas carry only the share.
        public let args: [String]
        public let kind: Kind
    }

    /// The recipient scheme a stanza belongs to. `label`/icon live in the app
    /// layer, keeping this module UI-free.
    public enum Kind: Sendable, Hashable {
        case x25519                 // native age recipient (age1…)
        case passphrase             // scrypt
        case sshEd25519
        case sshRSA
        case secureEnclave          // piv-p256 (age-plugin-se / age1se1…)
        case p256Tag                // p256tag (YubiKey-compatible / age1p256tag1…)
        case postQuantum(String)    // mlkem768x25519, mlkem768p256tag, …
        case other(String)

        init(stanzaType type: String) {
            switch type {
            case "X25519": self = .x25519
            case "scrypt": self = .passphrase
            case "ssh-ed25519": self = .sshEd25519
            case "ssh-rsa": self = .sshRSA
            case "piv-p256": self = .secureEnclave
            case "p256tag": self = .p256Tag
            case "mlkem768x25519", "mlkem768p256tag": self = .postQuantum(type)
            default: self = .other(type)
            }
        }
    }

    /// A byte breakdown of the file, all measured on the binary (de-armored) form
    /// except `armorOverhead`, which is the extra bytes the ASCII armor adds.
    public struct Sizes: Sendable, Equatable {
        public let header: Int
        public let armorOverhead: Int
        public let encryptionOverhead: Int
        public let payload: Int
        /// The total file size (armored, if the file is armored).
        public var total: Int { header + armorOverhead + encryptionOverhead + payload }
    }
}

/// Parses an age file header to produce an `AgeFileInfo`. Independent of AgeKit's
/// stream machinery so it works on a bare `Data` (or a partial Quick Look read).
public enum AgeFileInspector {
    /// age STREAM constants (see age's `internal/stream`).
    private static let chunkSize = 64 * 1024
    private static let tagSize = 16     // ChaCha20-Poly1305 tag per chunk
    private static let nonceSize = 16   // STREAM nonce prefixing the payload

    /// Inspect the file at `url`, reading it lazily.
    public static func inspect(contentsOf url: URL) throws -> AgeFileInfo {
        try inspect(Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Inspect age file bytes (binary or ASCII-armored).
    ///
    /// - Throws: `AssuageError.invalidAgeFile` if the header can't be parsed.
    public static func inspect(_ data: Data) throws -> AgeFileInfo {
        let isArmored = Armoring.isArmored(data)
        let binary = isArmored ? try Armoring.normalizedBinary(data) : data

        let (stanzas, headerLength) = try parseHeader(binary)
        let stanzaTypes = stanzas.map(\.type)

        let recipients = stanzas.enumerated().compactMap { index, stanza -> AgeFileInfo.Recipient? in
            guard !isGrease(stanza.type) else { return nil }
            return AgeFileInfo.Recipient(id: index, type: stanza.type, args: stanza.args, kind: .init(stanzaType: stanza.type))
        }

        return AgeFileInfo(
            isArmored: isArmored,
            version: AgeFileInfo.currentVersion,
            stanzaTypes: stanzaTypes,
            recipients: recipients,
            postQuantum: postQuantum(of: stanzaTypes),
            sizes: sizes(headerLength: headerLength, binaryCount: binary.count, originalCount: data.count, isArmored: isArmored)
        )
    }

    /// age/rage insert a stanza with a random `*-grease` type into every header;
    /// it's obfuscation padding, not a real recipient.
    static func isGrease(_ type: String) -> Bool { type.hasSuffix("-grease") }

    /// Mirror `age-inspect`'s post-quantum classification over the raw types.
    private static func postQuantum(of stanzaTypes: [String]) -> AgeFileInfo.PostQuantum {
        var result = AgeFileInfo.PostQuantum.unknown
        for type in stanzaTypes {
            switch type {
            case "X25519", "ssh-rsa", "ssh-ed25519", "p256tag", "piv-p256":
                result = .no
            case "mlkem768x25519", "scrypt", "mlkem768p256tag":
                if result != .no { result = .yes }
            default:
                break
            }
        }
        return result
    }

    /// Scan the header's cleartext lines: validate the intro, collect each `-> `
    /// stanza's type, and stop at the `---` footer. Body lines (wrapped base64,
    /// which can never start with `-`) are skipped. Returns the stanza types and
    /// the byte offset where the payload begins.
    ///
    /// Works over `Data` directly (only the header region is read) so a mapped,
    /// multi-gigabyte file is never copied into memory.
    private static func parseHeader(_ data: Data) throws -> (stanzas: [(type: String, args: [String])], headerLength: Int) {
        let newline = UInt8(ascii: "\n")
        var cursor = data.startIndex

        /// Read one `\n`-terminated line; returns its text and the payload offset
        /// (bytes consumed from the start) just past it.
        func readLine() -> (text: String, offset: Int)? {
            guard cursor < data.endIndex else { return nil }
            let lineEnd = data[cursor..<data.endIndex].firstIndex(of: newline) ?? data.endIndex
            let text = String(decoding: data[cursor..<lineEnd], as: UTF8.self)
            cursor = lineEnd < data.endIndex ? data.index(after: lineEnd) : lineEnd
            return (text, cursor - data.startIndex)
        }

        guard let intro = readLine(), intro.text == AgeFileInfo.currentVersion else {
            throw AssuageError.invalidAgeFile
        }

        var stanzas: [(type: String, args: [String])] = []
        while let (line, offset) = readLine() {
            if line.hasPrefix("-> ") {
                let fields = line.dropFirst(3).split(separator: " ", omittingEmptySubsequences: true)
                if let type = fields.first {
                    stanzas.append((String(type), fields.dropFirst().map(String.init)))
                }
            } else if line.hasPrefix("---") {
                return (stanzas, offset)
            }
            // Otherwise a stanza body line — skip it.
        }
        // Ran out of bytes before the footer: not a complete, valid header.
        throw AssuageError.invalidAgeFile
    }

    private static func sizes(headerLength: Int, binaryCount: Int, originalCount: Int, isArmored: Bool) -> AgeFileInfo.Sizes? {
        let payloadTotal = binaryCount - headerLength
        guard payloadTotal >= 0, let overhead = streamOverhead(payloadTotal) else { return nil }
        return AgeFileInfo.Sizes(
            header: headerLength,
            armorOverhead: isArmored ? max(0, originalCount - binaryCount) : 0,
            encryptionOverhead: overhead,
            payload: payloadTotal - overhead
        )
    }

    /// Bytes the age STREAM adds on top of the plaintext: the 16-byte nonce plus
    /// one 16-byte tag per 64 KiB chunk. `nil` if `payloadSize` isn't a valid
    /// STREAM size (truncated, or header only).
    private static func streamOverhead(_ payloadSize: Int) -> Int? {
        guard payloadSize >= nonceSize else { return nil }
        guard let plaintext = plaintextSize(payloadSize - nonceSize) else { return nil }
        return payloadSize - plaintext
    }

    /// Invert age's chunk accounting to recover the plaintext size, validating
    /// that `encryptedSize` is a legal number of full-plus-tag chunks.
    private static func plaintextSize(_ encryptedSize: Int) -> Int? {
        let encChunkSize = chunkSize + tagSize
        let chunks = (encryptedSize + encChunkSize - 1) / encChunkSize
        let plaintext = encryptedSize - chunks * tagSize
        guard plaintext >= 0 else { return nil }
        var expectedChunks = (plaintext + chunkSize - 1) / chunkSize
        if plaintext == 0 { expectedChunks = 1 } // the empty-plaintext single-chunk case
        guard expectedChunks == chunks else { return nil }
        return plaintext
    }
}
