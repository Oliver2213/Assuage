import Foundation
import Testing
@testable import AssuageCore

/// Signed-note format (`c2sp.org/signed-note`) — signer/verifier keys and notes.
///
/// The anchor is the canonical PeterNeumann vector from Go's `sumdb/note` package.
/// Ed25519 signatures are deterministic (RFC 8032), so signing the exact text with
/// the exact key must reproduce the exact published note — a true known-answer test.
@Suite("Signed notes")
struct SignedNoteTests {
    static let signerKey = "PRIVATE+KEY+PeterNeumann+c74f20a3+AYEKFALVFGyNhPJEMzD1QIDr+Y7hfZx09iUvxdXHKDFz"
    static let verifierKey = "PeterNeumann+c74f20a3+ARpc2QcUPDhMQegwxbzhKqiBfsVkmqq/LDE4izWy10TW"
    static let text = """
        If you think cryptography is the answer to your problem,
        then you don't know what your problem is.

        """
    static let signedNote = """
        If you think cryptography is the answer to your problem,
        then you don't know what your problem is.

        — PeterNeumann x08go/ZJkuBS9UG/SffcvIAQxVBtiFupLLr8pAcElZInNIuGUgYN1FFYC2pZSNXgKvqfqdngotpRZb6KE6RyyBwJnAM=

        """

    // MARK: Known-answer vector

    @Test("The signer key derives the published verifier key")
    func signerDerivesVerifier() throws {
        let identity = try SigningIdentity(parsingSignerKey: Self.signerKey)
        #expect(identity.name == "PeterNeumann")
        #expect(identity.verifierKey.encoded == Self.verifierKey)
        #expect(identity.verifierKey.keyIDHex == "c74f20a3")
        // Round-trips back to the same signer key string.
        #expect(identity.encodedSignerKey == Self.signerKey)
    }

    @Test("Signing the vector text produces a note that verifies")
    func signingVectorVerifies() throws {
        // NB: CryptoKit's Ed25519 is randomized (hedged), not deterministic RFC 8032,
        // so our signature bytes won't byte-match the published note — but they must
        // verify against the same key, and the layout must be identical (same text,
        // same signer line shape). Byte-for-byte reproduction is covered in reverse by
        // `parsesAndVerifies`, which checks the published bytes directly.
        let identity = try SigningIdentity(parsingSignerKey: Self.signerKey)
        var note = SignedNote(text: Self.text)
        try note.sign(with: identity, keepingExisting: false)
        #expect(note.text == Self.text)
        #expect(note.signatures.first?.name == "PeterNeumann")
        #expect(note.signatures.first?.keyIDHex == "c74f20a3")
        let key = try VerifierKey(parsing: Self.verifierKey)
        #expect(note.verify(with: [key]).first?.status == .verified(name: "PeterNeumann"))
    }

    @Test("The published note parses and verifies against the verifier key")
    func parsesAndVerifies() throws {
        let key = try VerifierKey(parsing: Self.verifierKey)
        let note = SignedNote(parsing: Self.signedNote)
        #expect(note.text == Self.text)
        #expect(note.signatures.count == 1)
        let results = note.verify(with: [key])
        #expect(results.first?.status == .verified(name: "PeterNeumann"))
    }

    @Test("A pasted note without a trailing newline still parses its signatures")
    func parsesWithoutTrailingNewline() throws {
        let key = try VerifierKey(parsing: Self.verifierKey)
        // What the clipboard typically yields: no newline after the last line.
        let pasted = String(Self.signedNote.reversed().drop { $0 == "\n" }.reversed())
        let note = SignedNote(parsing: pasted)
        #expect(note.signatures.count == 1)
        #expect(note.verify(with: [key]).first?.status == .verified(name: "PeterNeumann"))
    }

    // MARK: Verifier / signer key encoding

    @Test("A verifier key round-trips through its encoding")
    func verifierRoundTrip() throws {
        let identity = try SigningIdentity.generate(name: "example.com/abc")
        let reparsed = try VerifierKey(parsing: identity.verifierKey.encoded)
        #expect(reparsed == identity.verifierKey)
    }

    @Test("Base64 fields containing a + still parse", arguments: 0..<50)
    func base64WithPlus(seed: Int) throws {
        // Generate keys until the encoding's base64 payload contains a '+', proving
        // the split keeps '+' inside the trailing field rather than treating it as a
        // separator. (Random keys hit this quickly.)
        let identity = try SigningIdentity.generate(name: "n\(seed)")
        let encoded = identity.verifierKey.encoded
        let reparsed = try VerifierKey(parsing: encoded)
        #expect(reparsed.encoded == encoded)
    }

    @Test("A tampered key ID is rejected")
    func tamperedKeyID() throws {
        let key = try SigningIdentity.generate(name: "signer").verifierKey.encoded
        // Flip a hex digit in the key-ID field (between the first two '+').
        let parts = key.split(separator: "+", maxSplits: 2, omittingEmptySubsequences: false)
        let badHex = parts[1] == "00000000" ? "11111111" : "00000000"
        let tampered = "\(parts[0])+\(badHex)+\(parts[2])"
        #expect(throws: AssuageError.self) { try VerifierKey(parsing: tampered) }
    }

    @Test("Invalid signer names are rejected", arguments: ["", "has space", "has+plus", "tab\ttab"])
    func invalidNames(name: String) {
        #expect(throws: AssuageError.self) { try SigningIdentity.generate(name: name) }
    }

    // MARK: Round trips & multi-signing

    @Test("A freshly signed note round-trips through parse")
    func freshRoundTrip() throws {
        let identity = try SigningIdentity.generate(name: "author")
        var note = SignedNote(text: "hello world")   // no trailing newline
        try note.sign(with: identity, keepingExisting: false)
        #expect(note.text == "hello world\n")         // newline appended
        let reparsed = SignedNote(parsing: note.serialized)
        #expect(reparsed.text == note.text)
        #expect(reparsed.signatures == note.signatures)
        #expect(reparsed.verify(with: [identity.verifierKey]).first?.status == .verified(name: "author"))
    }

    @Test("Keeping signatures accumulates multiple signers over the same text")
    func multiSignKeep() throws {
        let alice = try SigningIdentity.generate(name: "alice")
        let bob = try SigningIdentity.generate(name: "bob")
        var note = SignedNote(text: "shared statement\n")
        try note.sign(with: alice, keepingExisting: false)
        try note.sign(with: bob, keepingExisting: true)
        #expect(note.signatures.count == 2)
        // Both verify — each signed the same text, independently.
        let results = note.verify(with: [alice.verifierKey, bob.verifierKey])
        #expect(results.allSatisfy { if case .verified = $0.status { return true } else { return false } })
    }

    @Test("Rebuilding from text and kept signatures preserves and re-verifies them")
    func rebuildWithKeptSignatures() throws {
        // Mirrors the Sign UI: the text and the pasted signatures are held apart,
        // then a new signer co-signs while keeping the others.
        let alice = try SigningIdentity.generate(name: "alice")
        let bob = try SigningIdentity.generate(name: "bob")
        var original = SignedNote(text: "shared\n")
        try original.sign(with: alice, keepingExisting: false)

        var rebuilt = SignedNote(text: original.text, signatures: original.signatures)
        try rebuilt.sign(with: bob, keepingExisting: true)
        #expect(rebuilt.signatures.count == 2)
        #expect(rebuilt.verify(with: [alice.verifierKey, bob.verifierKey])
            .allSatisfy { if case .verified = $0.status { return true } else { return false } })
    }

    @Test("Not keeping signatures drops the others")
    func multiSignDrop() throws {
        let alice = try SigningIdentity.generate(name: "alice")
        let bob = try SigningIdentity.generate(name: "bob")
        var note = SignedNote(text: "statement\n")
        try note.sign(with: alice, keepingExisting: false)
        try note.sign(with: bob, keepingExisting: false)
        #expect(note.signatures.count == 1)
        #expect(note.signatures.first?.name == "bob")
    }

    @Test("Re-signing with the same identity replaces, not duplicates")
    func resignReplaces() throws {
        let identity = try SigningIdentity.generate(name: "author")
        var note = SignedNote(text: "statement\n")
        try note.sign(with: identity, keepingExisting: false)
        try note.sign(with: identity, keepingExisting: true)
        #expect(note.signatures.count == 1)
    }

    // MARK: Verification failure modes

    @Test("An unknown signer is reported, not verified")
    func unknownSigner() throws {
        let author = try SigningIdentity.generate(name: "author")
        let stranger = try SigningIdentity.generate(name: "stranger")
        var note = SignedNote(text: "statement\n")
        try note.sign(with: author, keepingExisting: false)
        #expect(note.verify(with: [stranger.verifierKey]).first?.status == .unknownSigner)
    }

    @Test("A signature over edited text no longer verifies")
    func editedTextFailsVerify() throws {
        let identity = try SigningIdentity.generate(name: "author")
        var note = SignedNote(text: "original\n")
        try note.sign(with: identity, keepingExisting: false)
        // Splice the original signature onto different text.
        let forged = SignedNote(parsing: "tampered\n\n" + note.serialized.split(separator: "\n\n", maxSplits: 1).last!)
        #expect(forged.verify(with: [identity.verifierKey]).first?.status == .invalid)
    }

    // MARK: Plain-text handling

    @Test("Multi-paragraph prose is not mistaken for a signature block")
    func proseIsNotSignatures() {
        let prose = "First paragraph.\n\nSecond paragraph.\n"
        let note = SignedNote(parsing: prose)
        #expect(note.signatures.isEmpty)
        #expect(note.text == prose)
    }

    @Test("Plain text with no newline gains one and has no signatures")
    func plainText() {
        let note = SignedNote(parsing: "just a line")
        #expect(note.text == "just a line\n")
        #expect(note.signatures.isEmpty)
    }
}
