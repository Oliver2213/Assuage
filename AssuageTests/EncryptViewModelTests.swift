import Foundation
import Testing
import AssuageCore
@testable import Assuage

@MainActor
@Suite("EncryptViewModel")
struct EncryptViewModelTests {

    @Test("Armored message produces text output that round-trips")
    func armoredMessage() async throws {
        let identity = AgeIdentity.generateX25519()
        let viewModel = EncryptViewModel()
        viewModel.armored = true

        await viewModel.encryptMessage("hello world", to: [identity.recipient])

        guard case .text(let armored)? = viewModel.output else {
            Issue.record("expected .text output, got \(String(describing: viewModel.output))")
            return
        }
        #expect(armored.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----"))
        #expect(!viewModel.isErrorPresented)

        let plaintext = try Cipher.decrypt(Data(armored.utf8), with: [identity])
        #expect(String(decoding: plaintext, as: UTF8.self) == "hello world")
    }

    @Test("Non-armored message produces binary output")
    func binaryMessage() async {
        let identity = AgeIdentity.generateX25519()
        let viewModel = EncryptViewModel()
        viewModel.armored = false

        await viewModel.encryptMessage("hi", to: [identity.recipient])

        guard case .binary? = viewModel.output else {
            Issue.record("expected .binary output")
            return
        }
        #expect(!viewModel.isErrorPresented)
    }

    @Test("Encrypting with no recipients surfaces an error")
    func noRecipients() async {
        let viewModel = EncryptViewModel()
        await viewModel.encryptMessage("hi", to: [])

        #expect(viewModel.output == nil)
        #expect(viewModel.isErrorPresented)
        #expect(!viewModel.errorMessage.isEmpty)
    }

    @Test("Encrypting files writes .age files and reports a summary")
    func encryptFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encrypt-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let identity = AgeIdentity.generateX25519()
        let a = directory.appendingPathComponent("a.txt")
        let b = directory.appendingPathComponent("b.txt")
        try Data("aaa".utf8).write(to: a)
        try Data("bbb".utf8).write(to: b)

        let viewModel = EncryptViewModel()
        await viewModel.encryptFiles([a, b], to: [identity.recipient])

        #expect(FileManager.default.fileExists(atPath: a.appendingPathExtension("age").path))
        #expect(FileManager.default.fileExists(atPath: b.appendingPathExtension("age").path))
        #expect(viewModel.fileStatus == "Encrypted 2 of 2 files.")
        #expect(!viewModel.isErrorPresented)
    }

    @Test("Passphrase message succeeds and round-trips")
    func passphraseMessage() async throws {
        let viewModel = EncryptViewModel()
        viewModel.armored = true
        viewModel.workFactor = 10 // keep scrypt fast in tests

        let ok = await viewModel.encryptMessage("hush", passphrase: "correct horse")
        #expect(ok)
        guard case .text(let armored)? = viewModel.output else {
            Issue.record("expected .text output, got \(String(describing: viewModel.output))")
            return
        }
        let plaintext = try Cipher.decrypt(Data(armored.utf8), passphrase: "correct horse")
        #expect(String(decoding: plaintext, as: UTF8.self) == "hush")
    }
}
