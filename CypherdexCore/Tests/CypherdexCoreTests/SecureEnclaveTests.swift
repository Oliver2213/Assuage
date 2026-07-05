import Foundation
import Testing
@testable import CypherdexCore

/// Real Secure Enclave round trips. Skipped on Macs without a Secure Enclave.
/// Uses `.none` access control so tests run headless without a Touch ID prompt.
@Suite("Secure Enclave", .enabled(if: SecureEnclaveKeys.isAvailable))
struct SecureEnclaveTests {

    @Test("Generated SE identity has the expected shape")
    func generatedShape() throws {
        let identity = try AgeIdentity.generateSecureEnclave(label: "SE key", accessControl: .none)
        #expect(identity.source == .secureEnclave)
        #expect(identity.recipient.kind == .secureEnclave)
        #expect(identity.recipient.encoding.hasPrefix("age1se1"))
        #expect(identity.requiresPresence == false)
        guard case .secureEnclave(let idString, let ac) = identity.material else {
            Issue.record("expected secureEnclave material"); return
        }
        #expect(idString.hasPrefix("AGE-PLUGIN-SE-1"))
        #expect(ac == .none)
    }

    @Test("Encrypt to an SE recipient and decrypt with the SE identity")
    func secureEnclaveRoundTrip() throws {
        let identity = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let message = Data("enclave secret".utf8)

        let ciphertext = try Cipher.encrypt(message, to: [identity.recipient])
        let plaintext = try Cipher.decrypt(ciphertext, with: [identity])
        #expect(plaintext == message)
    }

    @Test("A different SE identity cannot decrypt")
    func wrongSecureEnclaveIdentity() throws {
        let owner = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let stranger = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let ciphertext = try Cipher.encrypt(Data("mine".utf8), to: [owner.recipient])

        #expect(Cipher.canDecrypt(ciphertext, with: [owner]))
        #expect(!Cipher.canDecrypt(ciphertext, with: [stranger]))
        #expect(throws: (any Error).self) {
            _ = try Cipher.decrypt(ciphertext, with: [stranger])
        }
    }

    @Test("Mixed X25519 + Secure Enclave recipients on one file")
    func mixedRecipients() throws {
        let software = AgeIdentity.generateX25519(label: "software key")
        let enclave = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let message = Data("both can open this".utf8)

        let ciphertext = try Cipher.encrypt(message, to: [software.recipient, enclave.recipient])

        #expect(try Cipher.decrypt(ciphertext, with: [software]) == message)
        #expect(try Cipher.decrypt(ciphertext, with: [enclave]) == message)
    }

    @Test("Armored SE round trip")
    func armoredSecureEnclave() throws {
        let identity = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        let message = Data("armored enclave".utf8)
        let armored = try Cipher.encrypt(message, to: [identity.recipient], armored: true)
        #expect(String(decoding: armored.prefix(30), as: UTF8.self).hasPrefix("-----BEGIN AGE"))
        #expect(try Cipher.decrypt(armored, with: [identity]) == message)
    }

    @Test("age-formatted SE export includes the access-control line")
    func exportShape() throws {
        let identity = try AgeIdentity.generateSecureEnclave(label: "Laptop", accessControl: .none)
        let text = identity.ageFormatted()
        #expect(text.contains("# access control: none"))
        #expect(text.contains("# public key: age1se1"))
        #expect(text.contains("\nAGE-PLUGIN-SE-1"))
    }

    @Test("A Secure Enclave identity round-trips through export and re-import")
    func importRoundTrip() throws {
        // `.none` so the decrypt below runs headless (no presence prompt).
        let generated = try AgeIdentity.generateSecureEnclave(label: "Laptop", accessControl: .none)
        guard case .secureEnclave(let generatedIdentity, _) = generated.material else {
            Issue.record("expected secureEnclave material"); return
        }

        // Parse the exported identity file back into an importable key.
        let importable = AgeIdentity.importableKeys(from: generated.ageFormatted())
        #expect(importable.count == 1)
        let key = try #require(importable.first)
        #expect(key.recipient == generated.recipient)
        guard case .secureEnclave(let identityString, let accessControl) = key.secret else {
            Issue.record("expected a Secure Enclave importable key"); return
        }
        #expect(identityString == generatedIdentity)
        // The `# access control: none` comment is read back as metadata.
        #expect(accessControl == .none)

        // Committing it reconstructs a usable identity that still decrypts.
        let imported = try AgeIdentity(importing: key, label: "Imported", protection: .local)
        #expect(imported.source == .secureEnclave)
        #expect(imported.recipient == generated.recipient)

        let message = Data("re-imported enclave".utf8)
        let ciphertext = try Cipher.encrypt(message, to: [imported.recipient])
        #expect(try Cipher.decrypt(ciphertext, with: [imported]) == message)
    }

    @Test("A bare AGE-PLUGIN-SE-1 line (no comments) imports and defaults its access control")
    func importBareLine() throws {
        let generated = try AgeIdentity.generateSecureEnclave(accessControl: .none)
        guard case .secureEnclave(let bareLine, _) = generated.material else {
            Issue.record("expected secureEnclave material"); return
        }

        let importable = AgeIdentity.importableKeys(from: bareLine)
        let key = try #require(importable.first)
        #expect(key.recipient == generated.recipient)
        guard case .secureEnclave(_, let accessControl) = key.secret else {
            Issue.record("expected a Secure Enclave importable key"); return
        }
        // No comment to read, so the metadata falls back to the safe default.
        #expect(accessControl == .anyBiometryOrPasscode)
    }
}
