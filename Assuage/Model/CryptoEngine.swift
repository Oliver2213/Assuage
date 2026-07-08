import Foundation
import AssuageCore

/// Runs blocking crypto off the main actor while streaming progress back to the UI.
@MainActor
@Observable
final class CryptoEngine {
    private(set) var progress: CryptoProgress?
    private(set) var isRunning = false

    // MARK: Operations

    func encrypt(_ plaintext: Data, to recipients: [AgeRecipient], armored: Bool) async throws -> Data {
        try await run { try Cipher.encrypt(plaintext, to: recipients, armored: armored, progress: $0) }
    }

    func decrypt(_ ciphertext: Data, with identities: [AgeIdentity]) async throws -> Data {
        try await run { try Cipher.decrypt(ciphertext, with: identities, progress: $0) }
    }

    func encryptFile(at source: URL, to destination: URL, recipients: [AgeRecipient], armored: Bool) async throws {
        try await run {
            try Cipher.encryptFile(at: source, to: destination, recipients: recipients, armored: armored, progress: $0)
        }
    }

    func decryptFile(at source: URL, to destination: URL, identities: [AgeIdentity]) async throws {
        try await run {
            try Cipher.decryptFile(at: source, to: destination, identities: identities, progress: $0)
        }
    }

    // MARK: Passphrase operations

    func encrypt(_ plaintext: Data, passphrase: String, armored: Bool, workFactor: Int) async throws -> Data {
        try await run { try Cipher.encrypt(plaintext, passphrase: passphrase, armored: armored, workFactor: workFactor, progress: $0) }
    }

    func decrypt(_ ciphertext: Data, passphrase: String) async throws -> Data {
        try await run { try Cipher.decrypt(ciphertext, passphrase: passphrase, progress: $0) }
    }

    func encryptFile(at source: URL, to destination: URL, passphrase: String, armored: Bool, workFactor: Int) async throws {
        try await run {
            try Cipher.encryptFile(at: source, to: destination, passphrase: passphrase, armored: armored, workFactor: workFactor, progress: $0)
        }
    }

    func decryptFile(at source: URL, to destination: URL, passphrase: String) async throws {
        try await run {
            try Cipher.decryptFile(at: source, to: destination, passphrase: passphrase, progress: $0)
        }
    }

    // MARK: Driver

    /// Run `work` on a background task, forwarding its progress to `progress` on
    /// the main actor and returning its result.
    private func run<T: Sendable>(
        _ work: @Sendable @escaping (@escaping ProgressHandler) throws -> T
    ) async throws -> T {
        isRunning = true
        progress = nil
        defer {
            isRunning = false
            progress = nil
        }

        let (stream, continuation) = AsyncStream<CryptoProgress>.makeStream()
        let task = Task.detached(priority: .userInitiated) { () throws -> T in
            defer { continuation.finish() }
            return try work { continuation.yield($0) }
        }
        for await update in stream {
            progress = update
        }
        return try await task.value
    }
}
