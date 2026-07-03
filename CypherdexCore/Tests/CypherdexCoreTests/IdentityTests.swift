import Foundation
import Testing
@testable import CypherdexCore

@Suite("Identities and recipients")
struct IdentityTests {

    @Test("Generated identity is in-memory and derives a matching X25519 recipient")
    func generatedIdentity() {
        let identity = AgeIdentity.generateX25519(label: "Test key")
        #expect(identity.label == "Test key")
        #expect(identity.source == .memory)
        #expect(identity.recipient.kind == .x25519)
        #expect(identity.recipient.encoding.hasPrefix("age1"))
    }

    @Test("Importing a secret key reproduces the same public recipient")
    func importRoundTrip() throws {
        let generated = AgeIdentity.generateX25519()
        guard case .x25519(let secret, _) = generated.material else {
            Issue.record("expected x25519 material")
            return
        }

        let imported = try AgeIdentity(importingX25519: secret)
        #expect(imported.recipient == generated.recipient)
    }

    @Test("Importing garbage throws unrecognizedIdentity")
    func importGarbage() {
        #expect(throws: CypherdexError.unrecognizedIdentity("not-a-key")) {
            _ = try AgeIdentity(importingX25519: "not-a-key")
        }
    }

    @Test("Recipient parsing accepts age1 and rejects nonsense")
    func recipientParsing() throws {
        let identity = AgeIdentity.generateX25519()
        let parsed = try AgeRecipient(parsing: "  \(identity.recipient.encoding)\n")
        #expect(parsed == identity.recipient)
        #expect(parsed.kind == .x25519)

        #expect(throws: CypherdexError.self) {
            _ = try AgeRecipient(parsing: "ssh-ed25519 AAAA...")
        }
        #expect(throws: CypherdexError.self) {
            _ = try AgeRecipient(parsing: "")
        }
    }

    @Test("age-formatted export has the expected shape")
    func ageFormatted() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let generated = AgeIdentity.generateX25519(label: "My Laptop", created: created)
        let text = generated.ageFormatted()
        let lines = text.split(separator: "\n").map(String.init)

        #expect(lines[0] == "# Cypherdex age identity")
        #expect(lines.contains("# label: My Laptop"))
        #expect(lines.contains { $0.hasPrefix("# created: ") })
        #expect(lines.contains("# public key: \(generated.recipient.encoding)"))
        // The last line is the secret key itself.
        #expect(lines.last?.hasPrefix("AGE-SECRET-KEY-1") == true)

        // The exported text must re-import to the same identity.
        let reimported = try AgeIdentity(importingX25519: lines.last!)
        #expect(reimported.recipient == generated.recipient)
    }

    @Test("Public-key export contains only the recipient")
    func publicKeyExport() {
        let generated = AgeIdentity.generateX25519(label: "Shareable")
        let text = generated.publicKeyFile()
        #expect(text.contains(generated.recipient.encoding))
        #expect(!text.contains("AGE-SECRET-KEY"))
    }
}
