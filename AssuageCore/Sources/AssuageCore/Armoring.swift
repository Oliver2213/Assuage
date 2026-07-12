import Foundation

/// ASCII armoring for age files.
///
/// age's armor is exactly PEM-style base64: a fixed header and footer around the
/// binary payload base64-encoded and wrapped at 64 columns. We implement it
/// directly (rather than via AgeKit's stream Armor type) because it's a trivial,
/// non-cryptographic transform and this keeps the byte layout under our control.
enum Armoring {
    static let header = "-----BEGIN AGE ENCRYPTED FILE-----"
    static let footer = "-----END AGE ENCRYPTED FILE-----"
    /// The fixed magic that begins every binary age file (and every dearmored payload).
    static let binaryIntro = "age-encryption.org/v1\n"
    private static let columns = 64

    /// Does this data look like an armored age file?
    static func isArmored(_ data: Data) -> Bool {
        // The header is ASCII; check within a small prefix, tolerating leading whitespace.
        guard let prefix = String(data: data.prefix(128), encoding: .utf8) else { return false }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(header)
    }

    /// Does this data begin like a binary (unarmored) age file? Lets us accept
    /// unarmored age bytes pasted as text, and reject input that clearly isn't age.
    static func looksLikeBinary(_ data: Data) -> Bool {
        data.starts(with: Data(binaryIntro.utf8))
    }

    /// Wrap binary age bytes as an armored string (ends with a trailing newline).
    static func armor(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        var wrapped = ""
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: columns, limitedBy: base64.endIndex) ?? base64.endIndex
            wrapped += base64[index..<end]
            wrapped += "\n"
            index = end
        }
        return header + "\n" + wrapped + footer + "\n"
    }

    /// Extract the binary payload from an armored string.
    static func dearmor(_ text: String) throws -> Data {
        var base64 = ""
        var insideBody = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == header { insideBody = true; continue }
            if line == footer { break }
            if insideBody { base64 += line }
        }
        guard insideBody, let data = Data(base64Encoded: base64) else {
            throw AssuageError.unreadableAgeFile
        }
        return data
    }

    /// Return the binary age bytes for `data`, de-armoring first if necessary.
    ///
    /// Input that is neither armored nor a binary age file is rejected up front
    /// with `.invalidAgeFile`, so pasted junk fails with a clear message instead
    /// of a raw stream error deep inside the decoder.
    static func normalizedBinary(_ data: Data) throws -> Data {
        if isArmored(data) {
            guard let text = String(data: data, encoding: .utf8) else {
                throw AssuageError.unreadableAgeFile
            }
            return try dearmor(text)
        }
        guard looksLikeBinary(data) else { throw AssuageError.invalidAgeFile }
        return data
    }
}
