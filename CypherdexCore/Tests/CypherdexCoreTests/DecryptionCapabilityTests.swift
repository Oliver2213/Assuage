import Foundation
import CryptoKit
import Testing
import AgeKit
@testable import CypherdexCore

/// Header-only "can you decrypt this?" checks — no secrets, no Secure Enclave.
@Suite("Decryption capability")
struct DecryptionCapabilityTests {

    private func capability(_ file: Data, _ identities: [AgeIdentity]) throws -> DecryptionCapability {
        try DecryptionCapabilityChecker.capability(of: file, for: identities)
    }

    // MARK: SSH (definitive via public-key fingerprint)

    @Test("A file encrypted to a held SSH key is decryptable")
    func sshMatched() throws {
        let id = try AgeIdentity(importingSSHEd25519: SSHIdentityTests.plainPEM, label: "laptop")
        let file = try Cipher.encrypt(Data("hi".utf8), to: [id.recipient])
        let cap = try capability(file, [id])
        #expect(cap == .decryptable(matching: [id]))
        #expect(cap.isPlausible)
    }

    @Test("A file for a different SSH key is not decryptable")
    func sshNoMatch() throws {
        let mine = try AgeIdentity(importingSSHEd25519: SSHIdentityTests.plainPEM)
        let theirs = try AgeIdentity(importingSSHEd25519: SSHIdentityTests.encPEM, passphrase: SSHIdentityTests.encPassphrase)
        let file = try Cipher.encrypt(Data("hi".utf8), to: [theirs.recipient])
        #expect(try capability(file, [mine]) == .noMatchingKey)
    }

    @Test("Only the matching identity is reported among several")
    func sshMatchedAmongMany() throws {
        let a = try AgeIdentity(importingSSHEd25519: SSHIdentityTests.plainPEM, label: "a")
        let b = AgeIdentity.generateX25519(label: "b")
        let file = try Cipher.encrypt(Data("hi".utf8), to: [a.recipient])
        #expect(try capability(file, [b, a]) == .decryptable(matching: [a]))
    }

    // MARK: X25519 (anonymous — undetermined)

    @Test("An X25519 file is undetermined when we hold an X25519 key")
    func x25519Undetermined() throws {
        let id = AgeIdentity.generateX25519()
        let file = try Cipher.encrypt(Data("hi".utf8), to: [id.recipient])
        // Anonymous stanza: even the *actual* recipient can't be confirmed by header.
        #expect(try capability(file, [id]) == .undetermined)
    }

    @Test("An X25519 file is no-match when we hold no X25519 key")
    func x25519NoX25519Held() throws {
        let recipientOnly = AgeIdentity.generateX25519()
        let sshOnly = try AgeIdentity(importingSSHEd25519: SSHIdentityTests.plainPEM)
        let file = try Cipher.encrypt(Data("hi".utf8), to: [recipientOnly.recipient])
        #expect(try capability(file, [sshOnly]) == .noMatchingKey)
    }

    // MARK: Passphrase

    @Test("A passphrase file reports passphraseRequired")
    func passphrase() throws {
        let file = try Cipher.encrypt(Data("hi".utf8), passphrase: "pw", workFactor: 10)
        #expect(try capability(file, [AgeIdentity.generateX25519()]) == .passphraseRequired)
    }

    // MARK: Secure Enclave tag matching (public-only, no hardware)

    /// Build an SE-shaped identity around a plain P256 public key so the tag match
    /// can be exercised without a real enclave (only the public recipient is used).
    private func secureEnclaveIdentity(hrp: String) -> (identity: AgeIdentity, recipient: AgeRecipient) {
        let publicKey = P256.KeyAgreement.PrivateKey().publicKey
        let encoding = Bech32().encode(hrp: hrp, data: publicKey.compressedRepresentation)
        let recipient = AgeRecipient(kind: .secureEnclave, encoding: encoding)
        let identity = AgeIdentity(
            id: UUID(), label: "se", created: Date(),
            material: .secureEnclave(identity: "AGE-PLUGIN-SE-1", accessControl: .none),
            recipient: recipient
        )
        return (identity, recipient)
    }

    @Test("piv-p256: a file to a held SE key is decryptable via the SHA-256 tag")
    func secureEnclavePivMatched() throws {
        let (identity, recipient) = secureEnclaveIdentity(hrp: "age1se")
        let file = try Cipher.encrypt(Data("hi".utf8), to: [recipient])
        #expect(try capability(file, [identity]) == .decryptable(matching: [identity]))
    }

    @Test("p256tag: a file to a held SE key is decryptable via the HMAC tag")
    func secureEnclaveTagMatched() throws {
        let (identity, recipient) = secureEnclaveIdentity(hrp: "age1p256tag")
        let file = try Cipher.encrypt(Data("hi".utf8), to: [recipient])
        #expect(try capability(file, [identity]) == .decryptable(matching: [identity]))
    }

    @Test("A file to a different SE key is not decryptable")
    func secureEnclaveNoMatch() throws {
        let (identity, _) = secureEnclaveIdentity(hrp: "age1se")
        let (_, otherRecipient) = secureEnclaveIdentity(hrp: "age1se")
        let file = try Cipher.encrypt(Data("hi".utf8), to: [otherRecipient])
        #expect(try capability(file, [identity]) == .noMatchingKey)
    }
}
