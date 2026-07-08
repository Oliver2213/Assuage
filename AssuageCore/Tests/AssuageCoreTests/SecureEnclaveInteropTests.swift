import Foundation
import Testing
@testable import AssuageCore

/// Proves our in-process Secure Enclave crypto is wire-compatible with the real
/// `age-plugin-se`. Requires a Secure Enclave, a real age CLI, and a built
/// `age-plugin-se` binary; otherwise skipped.
@Suite("Secure Enclave interop with age-plugin-se",
       .enabled(if: SecureEnclaveKeys.isAvailable
                    && AgeCLI.locate() != nil
                    && AgePluginSE.directory() != nil))
struct SecureEnclaveInteropTests {

    @Test("Our SE ciphertext decrypts with the real age-plugin-se")
    func ourEncryptPluginDecrypt() throws {
        let cli = try #require(AgeCLI.locate())
        let pluginDir = try #require(AgePluginSE.directory())
        let dir = ScratchDir()
        let identity = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let message = Data("secure enclave crossing the wire".utf8)

        let cipher = dir.file("m.age")
        try Cipher.encrypt(message, to: [identity.recipient]).write(to: cipher)
        let idFile = dir.file("id.txt")
        try Data(identity.ageFormatted().utf8).write(to: idFile)

        let out = try cli.run(["-d", "-i", idFile.path, cipher.path], pluginDirectory: pluginDir)
        #expect(out == message)
    }

    @Test("age-plugin-se ciphertext decrypts with our SE identity")
    func pluginEncryptOurDecrypt() throws {
        let cli = try #require(AgeCLI.locate())
        let pluginDir = try #require(AgePluginSE.directory())
        let dir = ScratchDir()
        let identity = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let message = Data("wrapped by the reference plugin".utf8)

        let plain = dir.file("plain.txt")
        try message.write(to: plain)
        let cipher = dir.file("out.age")
        _ = try cli.run(
            ["-r", identity.recipient.encoding, "-o", cipher.path, plain.path],
            pluginDirectory: pluginDir
        )

        let decrypted = try Cipher.decrypt(Data(contentsOf: cipher), with: [identity])
        #expect(decrypted == message)
    }
}

/// Locates a built `age-plugin-se` binary's directory (must be named exactly
/// `age-plugin-se` on PATH for age to discover it).
enum AgePluginSE {
    static func directory() -> URL? {
        let candidates = [
            "\(NSHomeDirectory())/src/age-plugin-se/.build/release/age-plugin-se",
            "\(NSHomeDirectory())/src/age-plugin-se/.build/debug/age-plugin-se",
            "/opt/homebrew/bin/age-plugin-se",
            "/usr/local/bin/age-plugin-se",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return nil
    }
}
