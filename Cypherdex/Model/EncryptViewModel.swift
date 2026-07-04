import Foundation
import CypherdexCore

/// Drives the Encrypt panel. Owns presentation state and the encrypt orchestration;
/// the actual crypto lives in `CypherdexCore` (`Cipher`), so this has no view
/// dependencies and its methods take explicit parameters.
@MainActor
@Observable
final class EncryptViewModel {
    var armored = true
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

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
