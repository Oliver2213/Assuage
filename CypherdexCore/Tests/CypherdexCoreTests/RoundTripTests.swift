import Foundation
import Testing
@testable import CypherdexCore

@Suite("Encrypt / decrypt round trips")
struct RoundTripTests {

    @Test("Binary round trip to a single recipient")
    func binaryRoundTrip() throws {
        let identity = AgeIdentity.generateX25519()
        let message = Data("Hello, Cypherdex!".utf8)

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
        #expect(throws: CypherdexError.noRecipients) {
            _ = try Cipher.encrypt(Data("x".utf8), to: [])
        }
        let ciphertext = try Cipher.encrypt(Data("x".utf8), to: [AgeIdentity.generateX25519().recipient])
        #expect(throws: CypherdexError.noIdentities) {
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
}
