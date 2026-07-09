import Foundation
import Testing
@testable import AssuageCore

@Suite("Passphrase (scrypt) encryption")
struct PassphraseTests {
    static let pass = "correct horse battery staple"

    @Test("Round trip through a passphrase")
    func roundTrip() throws {
        let message = Data("passphrase secret".utf8)
        let cipher = try Cipher.encrypt(message, passphrase: Self.pass, workFactor: 10)
        let out = try Cipher.decrypt(cipher, passphrase: Self.pass)
        #expect(out == message)
    }

    @Test("Armored round trip through a passphrase")
    func armoredRoundTrip() throws {
        let message = Data("armored passphrase secret".utf8)
        let cipher = try Cipher.encrypt(message, passphrase: Self.pass, armored: true, workFactor: 10)
        #expect(Armoring.isArmored(cipher))
        let out = try Cipher.decrypt(cipher, passphrase: Self.pass)
        #expect(out == message)
    }

    @Test("The wrong passphrase is rejected")
    func wrongPassphrase() throws {
        let cipher = try Cipher.encrypt(Data("secret".utf8), passphrase: Self.pass, workFactor: 10)
        #expect(throws: AssuageError.incorrectPassphrase) {
            try Cipher.decrypt(cipher, passphrase: "not the passphrase")
        }
    }

    @Test("An empty passphrase is rejected")
    func emptyPassphrase() throws {
        #expect(throws: AssuageError.emptyPassphrase) {
            try Cipher.encrypt(Data("x".utf8), passphrase: "")
        }
        #expect(throws: AssuageError.emptyPassphrase) {
            try Cipher.decrypt(Data("x".utf8), passphrase: "")
        }
    }

    @Test("File round trip through a passphrase")
    func fileRoundTrip() throws {
        let dir = ScratchDir()
        let plain = dir.file("p.txt")
        let enc = dir.file("p.age")
        let dec = dir.file("p.out")
        let message = Data("file passphrase secret".utf8)
        try message.write(to: plain)
        try Cipher.encryptFile(at: plain, to: enc, passphrase: Self.pass, workFactor: 10)
        try Cipher.decryptFile(at: enc, to: dec, passphrase: Self.pass)
        #expect(try Data(contentsOf: dec) == message)
    }

    // Deterministic interop: a real `rage -p` file (passphrase below, work factor
    // 20) must decrypt with us — proves we read the age scrypt format as produced
    // by the reference CLI.
    @Test("A rage-produced passphrase file decrypts with us")
    func rageVectorDecrypts() throws {
        let cipher = try #require(Data(base64Encoded: Self.rageVectorBase64))
        let out = try Cipher.decrypt(cipher, passphrase: Self.pass)
        #expect(String(decoding: out, as: UTF8.self) == "scrypt interop message")
    }

    static let rageVectorBase64 =
        "YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IHNjcnlwdCB2bEJuUDdPSjRoalZKWnJpek5LQkpBIDIw" +
        "CmxwbVNheXZwanZPbmxOVHN6S0h0cVl5bHNRQXVzYnlsVEl0NGw1VnF4S2sKLS0tIGVEUG5CK3dB" +
        "R0lFT3pEbGhhOEhmVFozbFQ4QitZTjdKelVzdWNxMkRKaHcKxxHAczCqvse8DCzJ8ZUe0Eqdcb+" +
        "q8OHAM3y7JG3XPirIckOaiLDr/LrVU3qIFLl928b3vKZ0"
}
