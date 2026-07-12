import Foundation
import Testing
@testable import AssuageCore

@Suite("Encrypt / decrypt round trips")
struct RoundTripTests {

    @Test("Binary round trip to a single recipient")
    func binaryRoundTrip() throws {
        let identity = AgeIdentity.generateX25519()
        let message = Data("Hello, Assuage!".utf8)

        let ciphertext = try Cipher.encrypt(message, to: [identity.recipient])
        #expect(ciphertext != message)
        // Binary age files begin with the version intro line.
        #expect(String(decoding: ciphertext.prefix(21), as: UTF8.self) == "age-encryption.org/v1")

        let plaintext = try Cipher.decrypt(ciphertext, with: [identity])
        #expect(plaintext == message)
    }

    @Test("Armored round trip")
    func armoredRoundTrip() throws {
        let identity = AgeIdentity.generateX25519()
        let message = Data("armor me".utf8)

        let armored = try Cipher.encrypt(message, to: [identity.recipient], armored: true)
        let text = String(decoding: armored, as: UTF8.self)
        #expect(text.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----"))
        #expect(text.contains("-----END AGE ENCRYPTED FILE-----"))

        // Decryption transparently handles armored input.
        let plaintext = try Cipher.decrypt(armored, with: [identity])
        #expect(plaintext == message)
    }

    @Test("Encrypting to several recipients lets any one of them decrypt")
    func multipleRecipients() throws {
        let alice = AgeIdentity.generateX25519(label: "Alice")
        let bob = AgeIdentity.generateX25519(label: "Bob")
        let carol = AgeIdentity.generateX25519(label: "Carol")
        let message = Data("group secret".utf8)

        let ciphertext = try Cipher.encrypt(message, to: [alice.recipient, bob.recipient])

        #expect(try Cipher.decrypt(ciphertext, with: [alice]) == message)
        #expect(try Cipher.decrypt(ciphertext, with: [bob]) == message)
        // Carol was not a recipient.
        #expect(throws: (any Error).self) {
            _ = try Cipher.decrypt(ciphertext, with: [carol])
        }
    }

    @Test("A non-recipient cannot decrypt")
    func wrongIdentityThrows() throws {
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()
        let ciphertext = try Cipher.encrypt(Data("nope".utf8), to: [owner.recipient])

        #expect(throws: (any Error).self) {
            _ = try Cipher.decrypt(ciphertext, with: [stranger])
        }
    }

    @Test("Empty recipient / identity lists are rejected")
    func emptyInputs() throws {
        #expect(throws: AssuageError.noRecipients) {
            _ = try Cipher.encrypt(Data("x".utf8), to: [])
        }
        let ciphertext = try Cipher.encrypt(Data("x".utf8), to: [AgeIdentity.generateX25519().recipient])
        #expect(throws: AssuageError.noIdentities) {
            _ = try Cipher.decrypt(ciphertext, with: [])
        }
    }

    @Test("Larger payload round-trips across multiple chunks")
    func multiChunkRoundTrip() throws {
        let identity = AgeIdentity.generateX25519()
        // Larger than the 64 KiB chunk size to exercise the streaming loop.
        let message = Data((0..<(200 * 1024)).map { UInt8($0 & 0xFF) })

        let ciphertext = try Cipher.encrypt(message, to: [identity.recipient])
        let plaintext = try Cipher.decrypt(ciphertext, with: [identity])
        #expect(plaintext == message)
    }

    @Test("Text that isn't an age file at all is reported as not-an-age-file")
    func junkInputRejected() throws {
        let identity = AgeIdentity.generateX25519()
        #expect(throws: AssuageError.invalidAgeFile) {
            _ = try Cipher.decrypt(Data("just some pasted text".utf8), with: [identity])
        }
    }

    @Test("A binary age file pasted as text reads as recognized-but-damaged, not a raw stream error")
    func binaryPastedAsTextRejected() throws {
        let identity = AgeIdentity.generateX25519()
        let ciphertext = try Cipher.encrypt(Data("paste me wrong".utf8), to: [identity.recipient])

        // Simulate pasting the binary output into a text field: the ASCII header
        // survives the UTF-8 round-trip but the binary payload is mangled, exactly
        // as `Data(text.utf8)` does in the decrypt UI. The intro is still there, so
        // it's recognized as age content that simply couldn't be read.
        let pasted = Data(String(decoding: ciphertext, as: UTF8.self).utf8)
        #expect(pasted != ciphertext)
        #expect(throws: AssuageError.unreadableAgeFile) {
            _ = try Cipher.decrypt(pasted, with: [identity])
        }
    }

    @Test("A stranger's identity reports that none of your identities match")
    func noMatchingIdentityMessage() throws {
        let owner = AgeIdentity.generateX25519()
        let stranger = AgeIdentity.generateX25519()
        let ciphertext = try Cipher.encrypt(Data("nope".utf8), to: [owner.recipient])
        #expect(throws: AssuageError.noMatchingIdentity) {
            _ = try Cipher.decrypt(ciphertext, with: [stranger])
        }
    }
}
