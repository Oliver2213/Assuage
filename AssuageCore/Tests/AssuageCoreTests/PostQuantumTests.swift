import Foundation
import Testing
@testable import AssuageCore

@Suite("Post-quantum (X-Wing) identities")
struct PostQuantumTests {
    private let plaintext = Data("pqtest".utf8)

    @Test("Generate, encrypt, and decrypt a post-quantum identity")
    func roundTrip() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum(label: "pq")
        #expect(identity.recipient.kind == .postQuantum)
        #expect(identity.recipient.encoding.hasPrefix("age1pq1"))

        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        let decrypted = try Cipher.decrypt(encrypted, with: [identity])
        #expect(decrypted == plaintext)
    }

    @Test("A post-quantum file is flagged as post-quantum by the inspector")
    func inspectionReportsPostQuantum() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        let info = try AgeFileInspector.inspect(encrypted)
        #expect(info.postQuantum == .yes)
        #expect(info.stanzaTypes.contains("mlkem768x25519"))
    }

    @Test("A recipient string parses back as post-quantum")
    func recipientParses() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let recipient = try AgeRecipient(parsing: identity.recipient.encoding)
        #expect(recipient.kind == .postQuantum)
        #expect(recipient.encoding == identity.recipient.encoding)
    }

    @Test("A stranger's post-quantum identity does not decrypt the file")
    func wrongIdentityFails() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let stranger = try AgeIdentity.generatePostQuantum()
        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        #expect(throws: (any Error).self) {
            try Cipher.decrypt(encrypted, with: [stranger])
        }
    }
}
