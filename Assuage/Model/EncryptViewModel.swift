import Foundation
import AssuageCore

/// Drives the Encrypt panel. Owns presentation state and the encrypt orchestration;
/// the actual crypto lives in `AssuageCore` (`Cipher`), so this has no view
/// dependencies and its methods take explicit parameters.
@MainActor
@Observable
final class EncryptViewModel {
    var armored = true
    /// scrypt cost (log2 of iterations) for passphrase encryption.
    var workFactor = Cipher.defaultWorkFactor
    var output: CryptoOutput?
    var fileStatus: String?
    var errorMessage = ""
    var isErrorPresented = false

    private let engine = CryptoEngine()
    var isRunning: Bool { engine.isRunning }
    var progress: CryptoProgress? { engine.progress }

    /// Encrypt text to recipients, storing the result in `output`.
    func encryptMessage(_ text: String, to recipients: [AgeRecipient]) async {
        output = nil
        do {
            let data = try await engine.encrypt(Data(text.utf8), to: recipients, armored: armored)
            output = armored ? .text(String(decoding: data, as: UTF8.self)) : .binary(data)
        } catch {
            present(error)
        }
    }

    /// Encrypt each selected item to a sibling `.age`, reporting a summary in
    /// `fileStatus`. Folders are archived to a single `.zip` first (see
    /// `encryptEach`), so a folder becomes `<folder>.zip.age`.
    func encryptFiles(_ files: [URL], to recipients: [AgeRecipient]) async {
        guard !recipients.isEmpty, !files.isEmpty else { return }
        let succeeded = await encryptEach(files) { source, destination in
            try await self.engine.encryptFile(at: source, to: destination, recipients: recipients, armored: false)
        }
        fileStatus = Self.summary(succeeded, of: files.count)
    }

    // MARK: Passphrase

    /// Encrypt text with a passphrase. Returns whether it succeeded, so the view
    /// can clear the passphrase fields on success.
    @discardableResult
    func encryptMessage(_ text: String, passphrase: String) async -> Bool {
        output = nil
        do {
            let data = try await engine.encrypt(Data(text.utf8), passphrase: passphrase, armored: armored, workFactor: workFactor)
            output = armored ? .text(String(decoding: data, as: UTF8.self)) : .binary(data)
            return true
        } catch {
            present(error)
            return false
        }
    }

    /// Encrypt each selected item with a passphrase (folders archived first, as
    /// above). Returns whether every item succeeded.
    @discardableResult
    func encryptFiles(_ files: [URL], passphrase: String) async -> Bool {
        guard !files.isEmpty else { return false }
        let succeeded = await encryptEach(files) { source, destination in
            try await self.engine.encryptFile(at: source, to: destination, passphrase: passphrase, armored: false, workFactor: self.workFactor)
        }
        fileStatus = Self.summary(succeeded, of: files.count)
        return succeeded == files.count
    }

    // MARK: File orchestration

    /// One selected item resolved for encryption.
    private struct PreparedInput {
        /// The file to encrypt — the item itself, or a temporary archive of it.
        let source: URL
        /// Where the `.age` output is written, beside the original item.
        let destination: URL
        /// A temporary archive to delete once encryption finishes, if any.
        let temporaryArchive: URL?
    }

    /// Encrypt every item in `urls` with `encryptOne`, archiving folders first and
    /// cleaning up any temporary archives. Errors on one item are surfaced and the
    /// rest continue. Returns the count that succeeded.
    private func encryptEach(
        _ urls: [URL],
        encryptOne: (_ source: URL, _ destination: URL) async throws -> Void
    ) async -> Int {
        var succeeded = 0
        for url in urls {
            var prepared: PreparedInput?
            do {
                let input = try await prepareInput(url)
                prepared = input
                try await encryptOne(input.source, input.destination)
                succeeded += 1
            } catch {
                present(error)
            }
            if let archive = prepared?.temporaryArchive { FolderArchive.cleanUp(archive) }
        }
        return succeeded
    }

    /// Resolve one selected item for encryption. A folder is zipped (off the main
    /// actor) to a temporary `.zip` and targets `<folder>.zip.age`; a file targets
    /// `<file>.age` in place.
    private func prepareInput(_ url: URL) async throws -> PreparedInput {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AssuageError.ioFailure
        }
        guard isDirectory.boolValue else {
            return PreparedInput(source: url, destination: url.appendingPathExtension("age"), temporaryArchive: nil)
        }
        let archive = try await Task.detached { try FolderArchive.zip(url) }.value
        let destination = url.appendingPathExtension("zip").appendingPathExtension("age")
        return PreparedInput(source: archive, destination: destination, temporaryArchive: archive)
    }

    private static func summary(_ succeeded: Int, of total: Int) -> String {
        "Encrypted \(succeeded) of \(total) item\(total == 1 ? "" : "s")."
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
