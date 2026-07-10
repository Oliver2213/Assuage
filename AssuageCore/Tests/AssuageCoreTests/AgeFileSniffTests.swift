import Foundation
import Testing
@testable import AssuageCore

@Suite("Age file sniffing")
struct AgeFileSniffTests {
    private let plaintext = Data("hello world\n".utf8)

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }

    @Test("A binary age file is recognized")
    func binaryFile() throws {
        let identity = AgeIdentity.generateX25519(label: "k")
        let url = try write(try Cipher.encrypt(plaintext, to: [identity.recipient]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AgeFileInspector.isAgeFile(at: url))
    }

    @Test("An armored age file is recognized")
    func armoredFile() throws {
        let identity = AgeIdentity.generateX25519(label: "k")
        let url = try write(try Cipher.encrypt(plaintext, to: [identity.recipient], armored: true))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AgeFileInspector.isAgeFile(at: url))
    }

    @Test("A plaintext file is not mistaken for age")
    func plaintextFile() throws {
        let url = try write(Data("just some text, not encrypted\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!AgeFileInspector.isAgeFile(at: url))
    }

    @Test("A directory is not an age file")
    func directory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!AgeFileInspector.isAgeFile(at: dir))
    }
}
