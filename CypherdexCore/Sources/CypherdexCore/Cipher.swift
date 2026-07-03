import Foundation
import AgeKit

/// The core encrypt / decrypt / inspect service.
///
/// All methods are synchronous and throwing. AgeKit's streaming primitives are
/// blocking, so callers should run these off the main actor (e.g. in a
/// `Task.detached`) and marshal `CryptoProgress` back to the UI via the handler,
/// which is `@Sendable` for exactly that reason.
public enum Cipher {

    private static let chunkSize = 64 * 1024

    // MARK: In-memory

    /// Encrypt `plaintext` to one or more recipients, returning the age file bytes.
    public static func encrypt(
        _ plaintext: Data,
        to recipients: [AgeRecipient],
        armored: Bool = false,
        progress: ProgressHandler? = nil
    ) throws -> Data {
        let recipient = try recipients.makeAgeRecipient()
        let binary = try encryptToMemory(
            source: InputStream(data: plaintext),
            totalBytes: Int64(plaintext.count),
            recipient: recipient,
            progress: progress
        )
        return armored ? Data(Armoring.armor(binary).utf8) : binary
    }

    /// Decrypt an age file (binary or armored) with one or more identities.
    public static func decrypt(
        _ ciphertext: Data,
        with identities: [AgeIdentity],
        progress: ProgressHandler? = nil
    ) throws -> Data {
        let identity = try identities.makeAgeIdentity()
        let binary = try Armoring.normalizedBinary(ciphertext)
        let output = OutputStream.toMemory()
        output.open()
        try decryptCore(binary: binary, identity: identity, into: output, progress: progress)
        // Read the accumulated bytes only after closing, so the final flushed
        // chunk is included in the snapshot.
        output.close()
        guard let data = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw CypherdexError.ioFailure
        }
        return data
    }

    // MARK: File to file

    /// Encrypt a file to another file. Non-armored output streams to disk with
    /// constant memory; armored output buffers (armoring wraps the whole payload).
    public static func encryptFile(
        at source: URL,
        to destination: URL,
        recipients: [AgeRecipient],
        armored: Bool = false,
        progress: ProgressHandler? = nil
    ) throws {
        let recipient = try recipients.makeAgeRecipient()
        let totalBytes = fileSize(source)
        guard let input = InputStream(url: source) else { throw CypherdexError.ioFailure }

        if armored {
            let binary = try encryptToMemory(
                source: input, totalBytes: totalBytes, recipient: recipient, progress: progress
            )
            try Data(Armoring.armor(binary).utf8).write(to: destination)
        } else {
            guard let output = OutputStream(url: destination, append: false) else {
                throw CypherdexError.ioFailure
            }
            output.open()
            defer { output.close() }
            try encryptCore(source: input, totalBytes: totalBytes, recipient: recipient, into: output, progress: progress)
        }
    }

    /// Decrypt a file to another file.
    public static func decryptFile(
        at source: URL,
        to destination: URL,
        identities: [AgeIdentity],
        progress: ProgressHandler? = nil
    ) throws {
        let identity = try identities.makeAgeIdentity()
        // Load-and-de-armor when armored; otherwise stream straight off disk.
        let binary: Data
        if let peek = try? Data(contentsOf: source, options: .mappedIfSafe), Armoring.isArmored(peek) {
            binary = try Armoring.normalizedBinary(peek)
        } else {
            binary = try Data(contentsOf: source, options: .mappedIfSafe)
        }
        guard let output = OutputStream(url: destination, append: false) else {
            throw CypherdexError.ioFailure
        }
        output.open()
        defer { output.close() }
        try decryptCore(binary: binary, identity: identity, into: output, progress: progress)
    }

    // MARK: Inspection

    /// Whether any of `identities` is a recipient of this age file — determined by
    /// unwrapping the file key from the header only, without decrypting the payload.
    ///
    /// For X25519 this is cheap and local. (Secure Enclave identities arrive in
    /// phase 2 and will prompt for presence, or use a header tag-check.)
    public static func canDecrypt(_ ciphertext: Data, with identities: [AgeIdentity]) -> Bool {
        guard !identities.isEmpty else { return false }
        do {
            let identity = try identities.makeAgeIdentity()
            let binary = try Armoring.normalizedBinary(ciphertext)
            let input = InputStream(data: binary)
            input.open()
            defer { input.close() }
            // `decrypt` performs the unwrap + header-MAC check but reads no
            // plaintext until we pull from the reader, which we never do.
            _ = try Age.decrypt(src: input, identities: identity)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Core

    private static func encryptToMemory(
        source: InputStream,
        totalBytes: Int64?,
        recipient: any Recipient,
        progress: ProgressHandler?
    ) throws -> Data {
        let output = OutputStream.toMemory()
        output.open()
        try encryptCore(source: source, totalBytes: totalBytes, recipient: recipient, into: output, progress: progress)
        output.close()
        guard let data = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw CypherdexError.ioFailure
        }
        return data
    }

    /// Read plaintext from `source` in chunks, encrypt, and stream to `destination`
    /// (which the caller must have opened). Reports progress per chunk.
    private static func encryptCore(
        source: InputStream,
        totalBytes: Int64?,
        recipient: any Recipient,
        into destination: OutputStream,
        progress: ProgressHandler?
    ) throws {
        source.open()
        defer { source.close() }

        var dst = destination
        var writer = try Age.encrypt(dst: &dst, recipients: recipient)

        let clock = ProgressClock()
        var processed: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while true {
            let n = source.read(&buffer, maxLength: chunkSize)
            if n < 0 { throw source.streamError ?? CypherdexError.ioFailure }
            if n == 0 { break }
            var chunk = Data(bytes: buffer, count: n)
            _ = try writer.write(&chunk)
            processed += Int64(n)
            progress?(clock.snapshot(processed: processed, total: totalBytes))
        }
        try writer.close()
    }

    /// Decrypt `binary` and stream plaintext to `destination` (caller-opened).
    private static func decryptCore(
        binary: Data,
        identity: any Identity,
        into destination: OutputStream,
        progress: ProgressHandler?
    ) throws {
        let input = InputStream(data: binary)
        input.open()
        defer { input.close() }

        var reader = try Age.decrypt(src: input, identities: identity)

        let clock = ProgressClock()
        var processed: Int64 = 0
        // A read buffer of exactly one chunk means each `read` drains the current
        // decrypted chunk and pulls the next. AgeKit's reader signals end-of-stream
        // by throwing `.unexpectedEOF` on the read *after* the final chunk (it has
        // no "return 0" EOF), so we treat that specific error as a clean end while
        // letting real failures (bad MAC → `.decryptFailure`, `.trailingData`)
        // propagate.
        while true {
            var out = Data(count: chunkSize)
            let n: Int
            do {
                n = try reader.read(&out)
            } catch {
                if isCleanEndOfStream(error) { break }
                throw error
            }
            if n == 0 { break }
            try destination.writeFully(out.prefix(n))
            processed += Int64(n)
            progress?(clock.snapshot(processed: processed, total: nil))
        }
    }

    /// AgeKit's `StreamError` is `internal`, so we can't catch `.unexpectedEOF` by
    /// type. Match it by description; every other error is a genuine failure.
    private static func isCleanEndOfStream(_ error: any Error) -> Bool {
        "\(error)" == "unexpectedEOF"
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}
