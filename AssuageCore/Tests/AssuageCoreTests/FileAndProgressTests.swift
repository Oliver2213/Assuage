import Foundation
import Testing
@testable import AssuageCore

@Suite("File operations, progress, and inspection")
struct FileAndProgressTests {

    /// A scratch directory unique to each test, cleaned up on deinit.
    final class TempDir {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("assuage-tests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    @Test("File round trip preserves bytes")
    func fileRoundTrip() throws {
        let dir = TempDir()
        let identity = AgeIdentity.generateX25519()
        let original = Data((0..<(150 * 1024)).map { _ in UInt8.random(in: .min ... .max) })

        let plain = dir.file("secret.bin")
        let encrypted = dir.file("secret.bin.age")
        let restored = dir.file("restored.bin")
        try original.write(to: plain)

        try Cipher.encryptFile(at: plain, to: encrypted, recipients: [identity.recipient])
        try Cipher.decryptFile(at: encrypted, to: restored, identities: [identity])

        #expect(try Data(contentsOf: restored) == original)
    }

    @Test("Armored file round trip")
    func armoredFileRoundTrip() throws {
        let dir = TempDir()
        let identity = AgeIdentity.generateX25519()
        let original = Data("armored file contents".utf8)

        let plain = dir.file("note.txt")
        let encrypted = dir.file("note.txt.age")
        let restored = dir.file("restored.txt")
        try original.write(to: plain)

        try Cipher.encryptFile(at: plain, to: encrypted, recipients: [identity.recipient], armored: true)
        let armoredText = try String(contentsOf: encrypted, encoding: .utf8)
        #expect(armoredText.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----"))

        try Cipher.decryptFile(at: encrypted, to: restored, identities: [identity])
        #expect(try Data(contentsOf: restored) == original)
    }

    @Test("A failed decrypt leaves no partial file behind")
    func failedDecryptWritesNothing() throws {
        let dir = TempDir()
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()

        let encrypted = dir.file("secret.age")
        try Cipher.encrypt(Data("classified".utf8), to: [owner.recipient]).write(to: encrypted)

        // The real destination the app uses: the source minus its `.age` extension.
        let out = encrypted.deletingPathExtension() // …/secret
        #expect(throws: (any Error).self) {
            try Cipher.decryptFile(at: encrypted, to: out, identities: [stranger])
        }
        // No zero-byte turd left where the output would have gone.
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test("A failed decrypt leaves an existing destination untouched")
    func failedDecryptPreservesExisting() throws {
        let dir = TempDir()
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()

        let encrypted = dir.file("secret.age")
        try Cipher.encrypt(Data("classified".utf8), to: [owner.recipient]).write(to: encrypted)

        let out = encrypted.deletingPathExtension() // …/secret
        let sentinel = Data("do not clobber me".utf8)
        try sentinel.write(to: out)

        #expect(throws: (any Error).self) {
            try Cipher.decryptFile(at: encrypted, to: out, identities: [stranger])
        }
        #expect(try Data(contentsOf: out) == sentinel)
    }

    @Test("Progress is reported and reaches the total")
    func progressReporting() throws {
        let identity = AgeIdentity.generateX25519()
        let size = 300 * 1024
        let message = Data(repeating: 0xAB, count: size)

        final class Box: @unchecked Sendable {
            var updates: [CryptoProgress] = []
        }
        let box = Box()
        _ = try Cipher.encrypt(message, to: [identity.recipient]) { progress in
            box.updates.append(progress)
        }

        #expect(!box.updates.isEmpty)
        #expect(box.updates.last?.bytesProcessed == Int64(size))
        #expect(box.updates.last?.totalBytes == Int64(size))
        #expect(box.updates.last?.fractionCompleted == 1.0)
        #expect(box.updates.allSatisfy { $0.bytesPerSecond >= 0 })
    }

    @Test("canDecrypt reflects recipient membership without decrypting")
    func checkDecryptable() throws {
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()
        let ciphertext = try Cipher.encrypt(Data("classified".utf8), to: [owner.recipient])

        #expect(Cipher.canDecrypt(ciphertext, with: [owner]))
        #expect(!Cipher.canDecrypt(ciphertext, with: [stranger]))
        #expect(!Cipher.canDecrypt(ciphertext, with: []))
        // Works on armored input too.
        let armored = try Cipher.encrypt(Data("classified".utf8), to: [owner.recipient], armored: true)
        #expect(Cipher.canDecrypt(armored, with: [owner]))
        #expect(!Cipher.canDecrypt(armored, with: [stranger]))
    }
}
