import Foundation
import Testing
@testable import AssuageCore

@Suite("Age file inspection")
struct AgeFileInfoTests {
    private let plaintext = Data("hello world\n".utf8) // 12 bytes

    private func recipient(_ label: String = "k") -> AgeRecipient {
        AgeIdentity.generateX25519(label: label).recipient
    }

    @Test("A binary X25519 file reports its recipient, version, and payload size")
    func binaryX25519() throws {
        let r = recipient()
        let file = try Cipher.encrypt(plaintext, to: [r])
        let info = try AgeFileInspector.inspect(file)

        #expect(!info.isArmored)
        #expect(info.version == AgeFileInfo.currentVersion)
        #expect(info.recipients.map(\.kind) == [.x25519])
        #expect(info.stanzaTypes == ["X25519"])
        #expect(info.postQuantum == .no)
        #expect(!info.isPassphrase)
        // The size breakdown recovers the exact plaintext length.
        #expect(info.sizes?.payload == plaintext.count)
        #expect(info.sizes?.armorOverhead == 0)
        #expect(info.sizes?.total == file.count)
    }

    @Test("An armored file is flagged and carries armor overhead")
    func armored() throws {
        let file = try Cipher.encrypt(plaintext, to: [recipient()], armored: true)
        let info = try AgeFileInspector.inspect(file)

        #expect(info.isArmored)
        #expect(info.recipients.map(\.kind) == [.x25519])
        #expect((info.sizes?.armorOverhead ?? 0) > 0)
        #expect(info.sizes?.payload == plaintext.count)
        #expect(info.sizes?.total == file.count)
    }

    @Test("Multiple recipients are all listed, in order")
    func multipleRecipients() throws {
        let file = try Cipher.encrypt(plaintext, to: [recipient("a"), recipient("b")])
        let info = try AgeFileInspector.inspect(file)
        #expect(info.recipients.count == 2)
        #expect(info.recipients.allSatisfy { $0.kind == .x25519 })
    }

    @Test("A passphrase file reads as scrypt and post-quantum")
    func passphrase() throws {
        let file = try Cipher.encrypt(plaintext, passphrase: "correct horse", workFactor: 12)
        let info = try AgeFileInspector.inspect(file)

        #expect(info.recipients.map(\.kind) == [.passphrase])
        #expect(info.isPassphrase)
        #expect(info.postQuantum == .yes)
    }

    @Test("Grease stanzas are listed raw but excluded from recipients")
    func greaseExcluded() throws {
        // A header-only blob (no payload) with a real recipient and a grease stanza.
        let header = """
        age-encryption.org/v1
        -> X25519 TEturmvR3sZTefjfErfr8jJgdvSHxSDL16Bntd66DXo
        gxHIhpBRTLGYLmL1ea+CBrpuU7yZTntGdRP1nHConDo
        -> J^-grease h2 42
        lFbHM4K8dL9tDLifQ2v0w
        --- gGSJPdEXhGx6f0K1I0f3nRj0Rn5xJcH8pmnEclZ0uw

        """
        let info = try AgeFileInspector.inspect(Data(header.utf8))

        #expect(info.stanzaTypes == ["X25519", "J^-grease"])
        #expect(info.recipients.map(\.kind) == [.x25519])
        // Header only: the payload size can't be computed.
        #expect(info.sizes == nil)
    }

    @Test("Stanza types classify into the right kinds")
    func classification() {
        func kind(_ type: String) -> AgeFileInfo.Kind { .init(stanzaType: type) }
        #expect(kind("X25519") == .x25519)
        #expect(kind("scrypt") == .passphrase)
        #expect(kind("ssh-ed25519") == .sshEd25519)
        #expect(kind("ssh-rsa") == .sshRSA)
        #expect(kind("piv-p256") == .secureEnclave)
        #expect(kind("p256tag") == .p256Tag)
        #expect(kind("mlkem768x25519") == .postQuantum("mlkem768x25519"))
        #expect(kind("something-else") == .other("something-else"))
    }

    @Test("Non-age input is rejected")
    func rejectsGarbage() {
        #expect(throws: AssuageError.invalidAgeFile) {
            try AgeFileInspector.inspect(Data("not an age file at all\n".utf8))
        }
    }
}
