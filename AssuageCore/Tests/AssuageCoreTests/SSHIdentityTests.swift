import Foundation
import Testing
@testable import AssuageCore

/// End-to-end coverage of the SSH Ed25519 integration in AssuageCore: importing
/// an OpenSSH key as an identity, encrypting to an `ssh-ed25519` recipient, and
/// decrypting `rage`-produced files. Fixtures are the same fixed keypair used in
/// AgeKit's tests.
@Suite("SSH ed25519 identities & recipients")
struct SSHIdentityTests {

    static let authorizedKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEmujjJWkoywNI8VHfDrnAkhNZqBhv7JUNe9fdXpby74 cypherdex-test-plain"
    static let plaintext = "Cypherdex ssh-ed25519 interop vector v1"

    static let plainPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBJro4yVpKMsDSPFR3w65wJITWagYb+yVDXvX3V6W8u+AAAAJgJ5dF1CeXR
    dQAAAAtzc2gtZWQyNTUxOQAAACBJro4yVpKMsDSPFR3w65wJITWagYb+yVDXvX3V6W8u+A
    AAAEBCyKIU00Tw1b7QP602jmc6+XtTMTTGQM9tuA4J+FSa+EmujjJWkoywNI8VHfDrnAkh
    NZqBhv7JUNe9fdXpby74AAAAFGN5cGhlcmRleC10ZXN0LXBsYWluAQ==
    -----END OPENSSH PRIVATE KEY-----
    """
    static let plainRageVectorB64 =
        "YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IHNzaC1lZDI1NTE5IEU5d2U4dyBRZm1KaERmbWdKSmpUMUJIb0hXWDR0aGRhZnFSVDBKUFlSNm9zSENSK1g0ClNBMEFsNTdoYkdGbXBGL2pEL1R1MDdvUzVyRXR1d2pGVm5DM2xWNysvSXMKLT4gOlh8LWdyZWFzZSArWiB9IFs8TyN9IDxdeQpSeC9pY2I2QlVIVFlDS1JWNUlrTW5hbVI5NUxmakl4eks4K1dHeEM0L0VLUVY3elhkaFVxbjlZZ1lRcTUKLS0tIEh5UWp6cVZPMW1tOVpndFlZMWxoaDNNUmRRQTF5Q2ltTkltclJKNUdJZUkKbifBtrDXYDpzdHnebeBmSQsRjF/23BQtjnkzLM7spY87US0XxNd1Ty+DG4JQsqybZUZYaQz4SDd2qr7c2+4IiYe1spjgpwA="

    static let encPassphrase = "testpass"
    static let encPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAaGqOGhU
    BmRJZ9236kKNXpAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAINKsk9Qu8YaRTq58
    /IYSt/6bT8k/keQY0ihoVV5FWo5ZAAAAoJ8QKZ/MbNNNwgpukQveQyOmaw4Mm13ZskO3EG
    TALD/7+0pPF1MbVT7wIXBjXENohNLK4UGMuHb85Ll1k0m5djbXq1SdTxO9wSl1GcjohbxK
    f5dDovF+jKVGxR9VL3YK1rf0rgiB6IhU8zQkC+37brHtjXFCrtZJkyiqI74UkfCto6nCrx
    9qg60yQGXoEHYxYhZU4kWbTdBdTiiQ44D7PN4=
    -----END OPENSSH PRIVATE KEY-----
    """
    static let encRageVectorB64 =
        "YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IHNzaC1lZDI1NTE5IFRNamRqQSB3VGxkTlFYdHkxOUdZTnRpSXdQT2JKYkZxVXRoSk96bFRlVER1VVpFcWxBCkFLYTl5dG1haTM4emxIam9wYkxIWW1GUDkwVHE0MGF0YWY0Vnh5YkViSGMKLT4gQTduaFc7TlktZ3JlYXNlID56IiUsJmYgT087VThBIGBaKCcKbDJxVlo5TU5BdFlWWUNRNnJSVzVNc0xpUUZGTW5PTExWSzdFdndNL2F3ckFoZmRzUjNrQ3RBT1RTWmZSYWIrdQpFSmlpTytNb3RHZGZuc3R0Ci0tLSAzZ2hpZldwWFBMMmd2cUp0Z2RlbUJVcUp5bStvRnREYmtvUkNROERpNHRvCsNueLaEpKnTBCd8+HCLhslVS7HNmupNc3zA3zz/9B281IL8ksUljO6Tf2I5KxR/FwYXiLY8kz9yCNlcuQH9wUq5Gjxr2dwa"

    // MARK: Import + recipient shape

    @Test("Importing an OpenSSH key yields an ssh-ed25519 identity + recipient")
    func importShape() throws {
        let id = try AgeIdentity(importingSSHEd25519: Self.plainPEM, label: "laptop")
        #expect(id.recipient.kind == .sshEd25519)
        #expect(id.recipient.encoding == Self.authorizedKey)
        #expect(id.source == .keychain(synced: false))
        #expect(id.keychainSecret != nil)   // the base64 seed
        #expect(id.x25519Secret == nil)      // not an age-native secret
    }

    // MARK: Encrypt / decrypt through Cipher

    @Test("Encrypt to an ssh-ed25519 recipient and decrypt with the identity")
    func roundTripThroughCipher() throws {
        let id = try AgeIdentity(importingSSHEd25519: Self.plainPEM)
        let file = try Cipher.encrypt(Data(Self.plaintext.utf8), to: [id.recipient])
        #expect(Cipher.canDecrypt(file, with: [id]))
        let out = try Cipher.decrypt(file, with: [id])
        #expect(String(decoding: out, as: UTF8.self) == Self.plaintext)
    }

    @Test("A recipient added from a pasted ssh-ed25519 line encrypts")
    func recipientFromPastedLine() throws {
        let recipient = try AgeRecipient(parsing: Self.authorizedKey)
        let id = try AgeIdentity(importingSSHEd25519: Self.plainPEM)
        let file = try Cipher.encrypt(Data(Self.plaintext.utf8), to: [recipient])
        #expect(String(decoding: try Cipher.decrypt(file, with: [id]), as: UTF8.self) == Self.plaintext)
    }

    @Test("Decrypt a rage-produced file with an imported SSH identity")
    func decryptRageVector() throws {
        let id = try AgeIdentity(importingSSHEd25519: Self.plainPEM)
        let file = try #require(Data(base64Encoded: Self.plainRageVectorB64))
        #expect(Cipher.canDecrypt(file, with: [id]))
        #expect(String(decoding: try Cipher.decrypt(file, with: [id]), as: UTF8.self) == Self.plaintext)
    }

    // MARK: Passphrase-protected import

    @Test("Import a passphrase-protected key and decrypt with it")
    func passphraseProtectedImport() throws {
        let id = try AgeIdentity(importingSSHEd25519: Self.encPEM, passphrase: Self.encPassphrase)
        let file = try #require(Data(base64Encoded: Self.encRageVectorB64))
        #expect(String(decoding: try Cipher.decrypt(file, with: [id]), as: UTF8.self) == Self.plaintext)
    }

    @Test("A missing passphrase is reported so the UI can prompt")
    func missingPassphrase() {
        #expect(throws: CypherdexError.sshPassphraseRequired) {
            _ = try AgeIdentity(importingSSHEd25519: Self.encPEM)
        }
    }

    // MARK: Dedup, unsupported types, export round-trip

    @Test("Recipients dedupe by public key, ignoring the comment")
    func dedupeByPublicKey() throws {
        let a = try AgeRecipient(parsing: Self.authorizedKey)
        let renamed = Self.authorizedKey.replacingOccurrences(of: "cypherdex-test-plain", with: "different comment")
        let b = try AgeRecipient(parsing: renamed)
        #expect(a.id == b.id)
        #expect(a.encoding != b.encoding)   // comment preserved for display
    }

    @Test("ssh-rsa is rejected with a specific error")
    func unsupportedType() {
        #expect(throws: CypherdexError.unsupportedSSHKeyType("ssh-rsa")) {
            _ = try AgeRecipient(parsing: "ssh-rsa AAAAB3NzaC1yc2EAAAA test")
        }
    }

    // MARK: Import scan (file / clipboard)

    @Test("Scanning text finds an unencrypted OpenSSH key")
    func scanUnencrypted() throws {
        let keys = AgeIdentity.importableKeys(from: Self.plainPEM)
        #expect(keys.count == 1)
        #expect(keys.first?.recipient.encoding == Self.authorizedKey)
        let id = try AgeIdentity(importing: #require(keys.first), label: "k", protection: .local)
        #expect(id.recipient.kind == .sshEd25519)
    }

    @Test("An encrypted key is skipped by the scan but detected for a passphrase prompt")
    func scanEncrypted() throws {
        #expect(AgeIdentity.importableKeys(from: Self.encPEM).isEmpty)
        #expect(AgeIdentity.containsOpenSSHPrivateKey(Self.encPEM))
        let key = try AgeIdentity.importableSSHKey(fromOpenSSH: Self.encPEM, passphrase: Self.encPassphrase)
        if case .sshEd25519 = key.secret {} else { Issue.record("expected an ssh seed") }
    }

    @Test("Exporting re-emits an OpenSSH key that round-trips to the same identity")
    func exportRoundTrip() throws {
        let id = try AgeIdentity(importingSSHEd25519: Self.plainPEM, label: "laptop")
        let exported = id.ageFormatted()
        #expect(exported.contains("-----BEGIN OPENSSH PRIVATE KEY-----"))
        // Re-import the exported OpenSSH key and confirm the same public recipient.
        let reimported = try AgeIdentity(importingSSHEd25519: exported)
        #expect(reimported.recipient.id == id.recipient.id)
    }
}
