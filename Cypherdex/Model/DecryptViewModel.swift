import Foundation
import CypherdexCore

/// Drives the Decrypt panel. Owns presentation state and the decrypt / check
/// orchestration; the crypto lives in `CypherdexCore`, so this has no view
/// dependencies and its methods take explicit parameters.
@MainActor
@Observable
final class DecryptViewModel {
    var output: CryptoOutput?
    var statusMessage: String?
    var statusIsGood = true
    var errorMessage = ""
    var isErrorPresented = false

    private let engine = CryptoEngine()
    var isRunning: Bool { engine.isRunning }
    var progress: CryptoProgress? { engine.progress }

    /// Decrypt text with the given identities, storing the result in `output`.
    func decrypt(_ text: String, with identities: [AgeIdentity]) async {
        output = nil
        statusMessage = nil
        do {
            let plaintext = try await engine.decrypt(Data(text.utf8), with: identities)
            output = String(data: plaintext, encoding: .utf8).map(CryptoOutput.text) ?? .binary(plaintext)
        } catch {
            present(error)
        }
    }

    /// Report whether any identity is a recipient, without decrypting the payload.
    func check(_ text: String, with identities: [AgeIdentity]) async {
        output = nil
        let data = Data(text.utf8)
        // Run off the main actor: for Secure Enclave keys this touches the enclave.
        let canDecrypt = await Task.detached { Cipher.canDecrypt(data, with: identities) }.value
        statusIsGood = canDecrypt
        statusMessage = canDecrypt
            ? "One of your selected identities can decrypt this."
            : "None of your selected identities can decrypt this."
    }

    /// Decrypt each file next to the original, reporting a summary in `statusMessage`.
    func decryptFiles(_ files: [URL], with identities: [AgeIdentity]) async {
        guard !identities.isEmpty, !files.isEmpty else { return }
        var succeeded = 0
        for url in files {
            do {
                try await engine.decryptFile(at: url, to: Self.destination(for: url), identities: identities)
                succeeded += 1
            } catch {
                present(error)
            }
        }
        statusIsGood = succeeded == files.count
        statusMessage = "Decrypted \(succeeded) of \(files.count) file\(files.count == 1 ? "" : "s")."
    }

    /// Where a decrypted file is written: drop a `.age` suffix, else append `.decrypted`.
    static func destination(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "age" {
            return url.deletingPathExtension()
        }
        return url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".decrypted")
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}
