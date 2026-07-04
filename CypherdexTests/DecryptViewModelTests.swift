import Foundation
import Testing
import CypherdexCore
@testable import Cypherdex

@MainActor
@Suite("DecryptViewModel")
struct DecryptViewModelTests {

    private func armored(_ plaintext: Data, to recipient: AgeRecipient) throws -> String {
        String(decoding: try Cipher.encrypt(plaintext, to: [recipient], armored: true), as: UTF8.self)
    }

    @Test("Decrypting UTF-8 plaintext yields text output")
    func textOutput() async throws {
        let identity = AgeIdentity.generateX25519()
        let ciphertext = try armored(Data("secret note".utf8), to: identity.recipient)

        let viewModel = DecryptViewModel()
        await viewModel.decrypt(ciphertext, with: [identity])

        #expect(viewModel.output == .text("secret note"))
        #expect(!viewModel.isErrorPresented)
    }

    @Test("Decrypting non-text plaintext yields binary output")
    func binaryOutput() async throws {
        let identity = AgeIdentity.generateX25519()
        let raw = Data([0xFF, 0xFE, 0x00, 0x01, 0x80]) // invalid UTF-8
        let ciphertext = try armored(raw, to: identity.recipient)

        let viewModel = DecryptViewModel()
        await viewModel.decrypt(ciphertext, with: [identity])

        #expect(viewModel.output == .binary(raw))
    }

    @Test("Decrypting with the wrong identity surfaces an error")
    func wrongIdentity() async throws {
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()
        let ciphertext = try armored(Data("mine".utf8), to: owner.recipient)

        let viewModel = DecryptViewModel()
        await viewModel.decrypt(ciphertext, with: [stranger])

        #expect(viewModel.output == nil)
        #expect(viewModel.isErrorPresented)
    }

    @Test("Check reflects recipient membership")
    func check() async throws {
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()
        let ciphertext = try armored(Data("hi".utf8), to: owner.recipient)

        let viewModel = DecryptViewModel()
        await viewModel.check(ciphertext, with: [owner])
        #expect(viewModel.statusIsGood)

        await viewModel.check(ciphertext, with: [stranger])
        #expect(!viewModel.statusIsGood)
    }

    @Test("Decrypting files writes plaintext and reports a summary")
    func decryptFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("decrypt-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let identity = AgeIdentity.generateX25519()
        let original = Data("file contents".utf8)
        let plain = directory.appendingPathComponent("note.txt")
        try original.write(to: plain)
        let encrypted = directory.appendingPathComponent("note.txt.age")
        try Cipher.encryptFile(at: plain, to: encrypted, recipients: [identity.recipient])
        try FileManager.default.removeItem(at: plain) // ensure decrypt recreates it

        let viewModel = DecryptViewModel()
        await viewModel.decryptFiles([encrypted], with: [identity])

        let decrypted = DecryptViewModel.destination(for: encrypted)
        #expect(try Data(contentsOf: decrypted) == original)
        #expect(viewModel.statusMessage == "Decrypted 1 of 1 file.")
        #expect(viewModel.statusIsGood)
    }

    @Test("Decrypted destination strips .age or appends .decrypted")
    func destination() {
        #expect(DecryptViewModel.destination(for: URL(fileURLWithPath: "/x/secret.txt.age")).lastPathComponent == "secret.txt")
        #expect(DecryptViewModel.destination(for: URL(fileURLWithPath: "/x/blob.bin")).lastPathComponent == "blob.bin.decrypted")
    }
}
