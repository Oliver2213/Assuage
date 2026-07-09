import Foundation
import Testing
@testable import AssuageCore

@Suite("Folder archiving")
struct FolderArchiveTests {
    /// Make a throwaway folder with a couple of files and return its URL.
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("first\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("second\n".utf8).write(to: root.appendingPathComponent("b.txt"))
        return root
    }

    @Test("Zipping a folder yields a real, named .zip archive")
    func zipsFolder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        let archive = try FolderArchive.zip(folder)
        defer { FolderArchive.cleanUp(archive) }

        #expect(archive.pathExtension == "zip")
        #expect(archive.deletingPathExtension().lastPathComponent == "Notes")
        #expect(FileManager.default.fileExists(atPath: archive.path))

        // A pkzip archive starts with the "PK" local-file-header signature.
        let bytes = try Data(contentsOf: archive)
        #expect(bytes.prefix(2) == Data([0x50, 0x4B]))
        #expect(bytes.count > 0)
    }

    @Test("The archive survives an encrypt/decrypt round trip byte-for-byte")
    func roundTripsThroughAge() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        let archive = try FolderArchive.zip(folder)
        defer { FolderArchive.cleanUp(archive) }
        let zipped = try Data(contentsOf: archive)

        let identity = AgeIdentity.generateX25519(label: "k")
        let encrypted = try Cipher.encrypt(zipped, to: [identity.recipient])
        let decrypted = try Cipher.decrypt(encrypted, with: [identity])

        #expect(decrypted == zipped)
    }

    @Test("cleanUp removes the archive and its scratch directory")
    func cleanUpRemovesArchive() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        let archive = try FolderArchive.zip(folder)
        FolderArchive.cleanUp(archive)

        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(!FileManager.default.fileExists(atPath: archive.deletingLastPathComponent().path))
    }
}
