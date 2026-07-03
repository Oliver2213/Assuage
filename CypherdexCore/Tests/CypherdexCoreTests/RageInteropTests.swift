import Foundation
import Testing
@testable import CypherdexCore

/// Proves our age files interoperate with a real age implementation (`rage`).
/// Skipped automatically when no `rage`/`age` binary is on the system.
@Suite("Interop with a real age CLI", .enabled(if: AgeCLI.locate() != nil))
struct RageInteropTests {

    @Test("Our ciphertext decrypts with the real CLI")
    func ourEncryptTheirDecrypt() throws {
        let cli = try #require(AgeCLI.locate())
        let dir = ScratchDir()
        let identity = AgeIdentity.generateX25519(label: "interop")
        let message = Data("cross-implementation secret".utf8)

        let cipher = dir.file("msg.age")
        try Cipher.encrypt(message, to: [identity.recipient]).write(to: cipher)

        let idFile = dir.file("key.txt")
        try Data(identity.ageFormatted().utf8).write(to: idFile)

        let out = try cli.run(["-d", "-i", idFile.path, cipher.path])
        #expect(out == message)
    }

    @Test("The real CLI's ciphertext decrypts with us")
    func theirEncryptOurDecrypt() throws {
        let cli = try #require(AgeCLI.locate())
        let dir = ScratchDir()
        let identity = AgeIdentity.generateX25519(label: "interop")
        let message = Data("encrypted by rage".utf8)

        let plain = dir.file("plain.txt")
        try message.write(to: plain)
        let cipher = dir.file("out.age")
        _ = try cli.run(["-r", identity.recipient.encoding, "-o", cipher.path, plain.path])

        let decrypted = try Cipher.decrypt(Data(contentsOf: cipher), with: [identity])
        #expect(decrypted == message)
    }

    @Test("Our armored ciphertext decrypts with the real CLI")
    func ourArmoredTheirDecrypt() throws {
        let cli = try #require(AgeCLI.locate())
        let dir = ScratchDir()
        let identity = AgeIdentity.generateX25519()
        let message = Data("armored interop".utf8)

        let cipher = dir.file("msg.age")
        try Cipher.encrypt(message, to: [identity.recipient], armored: true).write(to: cipher)
        let idFile = dir.file("key.txt")
        try Data(identity.ageFormatted().utf8).write(to: idFile)

        let out = try cli.run(["-d", "-i", idFile.path, cipher.path])
        #expect(out == message)
    }
}

/// Locates and runs a real age CLI for interop tests.
struct AgeCLI {
    let url: URL

    /// Find `rage` or `age` on PATH or in common install locations.
    static func locate() -> AgeCLI? {
        let candidates = [
            "/opt/homebrew/bin/age", "/usr/local/bin/age", "/usr/bin/age",
            "\(NSHomeDirectory())/.cargo/bin/rage",
            "/opt/homebrew/bin/rage", "/usr/local/bin/rage",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return AgeCLI(url: URL(fileURLWithPath: path))
        }
        return nil
    }

    /// Run the CLI with `arguments`, returning stdout. Throws on non-zero exit.
    /// `pluginDirectory`, when set, is prepended to `PATH` so age plugins are found.
    func run(_ arguments: [String], pluginDirectory: URL? = nil) throws -> Data {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        if let pluginDirectory {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = pluginDirectory.path + ":" + (environment["PATH"] ?? "")
            process.environment = environment
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw CLIError.nonZeroExit(code: process.terminationStatus, stderr: err)
        }
        return data
    }

    enum CLIError: Error { case nonZeroExit(code: Int32, stderr: String) }
}

/// A scratch directory removed when the value is deallocated.
final class ScratchDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypherdex-interop-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
}
