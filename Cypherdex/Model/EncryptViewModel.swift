import Foundation
import CypherdexCore

/// Drives the Encrypt panel. Owns presentation state and the encrypt orchestration;
/// the actual crypto lives in `CypherdexCore` (`Cipher`), so this has no view
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

    /// Encrypt each file to `<file>.age`, reporting a summary in `fileStatus`.
    func encryptFiles(_ files: [URL], to recipients: [AgeRecipient]) async {
        guard !recipients.isEmpty, !files.isEmpty else { return }
        var succeeded = 0
        for url in files {
            do {
                try await engine.encryptFile(at: url, to: url.appendingPathExtension("age"), recipients: recipients, armored: false)
                succeeded += 1
            } catch {
                present(error)
            }
        }
        fileStatus = "Encrypted \(succeeded) of \(files.count) file\(files.count == 1 ? "" : "s")."
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

    /// Encrypt each file to `<file>.age` with a passphrase. Returns whether all
    /// files succeeded.
    @discardableResult
    func encryptFiles(_ files: [URL], passphrase: String) async -> Bool {
        guard !files.isEmpty else { return false }
        var succeeded = 0
        for url in files {
            do {
                try await engine.encryptFile(at: url, to: url.appendingPathExtension("age"), passphrase: passphrase, armored: false, workFactor: workFactor)
                succeeded += 1
            } catch {
                present(error)
            }
        }
        fileStatus = "Encrypted \(succeeded) of \(files.count) file\(files.count == 1 ? "" : "s")."
        return succeeded == files.count
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
