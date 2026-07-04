import Foundation
import Testing
@testable import CypherdexCore

@Suite("Identities and recipients")
struct IdentityTests {

    @Test("Generated identity is keychain-stored and derives a matching X25519 recipient")
    func generatedIdentity() {
        let identity = AgeIdentity.generateX25519(label: "Test key")
        #expect(identity.label == "Test key")
        #expect(identity.source == .keychain(synced: false))
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

    @Test("Importable-key parsing keeps valid keys and skips everything else")
    func importableKeys() {
        let a = AgeIdentity.generateX25519()
        let b = AgeIdentity.generateX25519()
        guard case .x25519(let secretA, _) = a.material,
              case .x25519(let secretB, _) = b.material else {
            Issue.record("expected x25519 material"); return
        }
        let text = """
        # Cypherdex age identity
        # created: 2026-01-01
        \(secretA)

        # another key
        \(secretB)
        ssh-ed25519 AAAA-not-an-age-key
        garbage
        """

        let keys = AgeIdentity.importableKeys(from: text)
        #expect(keys.count == 2)
        #expect(keys.map(\.recipient) == [a.recipient, b.recipient])
        #expect(AgeIdentity.importableKeys(from: "no keys here\n# comment").isEmpty)
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

    @Test("A recipients file lists each public key and no secret")
    func recipientsFile() {
        let a = AgeIdentity.generateX25519(label: "Laptop")
        let b = AgeIdentity.generateX25519(label: "Phone")
        let text = [a, b].recipientsFile(includeNames: false)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // One recipient per line, in order, and nothing else.
        #expect(lines.filter { !$0.isEmpty } == [a.recipient.encoding, b.recipient.encoding])
        #expect(!text.contains("AGE-SECRET-KEY"))
        #expect(!text.contains("#"))
        #expect(text.hasSuffix("\n"))
    }

    @Test("Names option precedes each labeled recipient with a comment")
    func recipientsFileWithNames() {
        let named = AgeIdentity.generateX25519(label: "Laptop")
        let unlabeled = AgeIdentity.generateX25519(label: "")
        let text = [named, unlabeled].recipientsFile(includeNames: true)
        let lines = text.split(separator: "\n").map(String.init)

        // The labeled key gets a `# label` comment above it; the unlabeled one
        // gets no comment, just its recipient.
        #expect(lines == ["# Laptop", named.recipient.encoding, unlabeled.recipient.encoding])
    }

    @Test("An empty identity list yields an empty recipients file")
    func recipientsFileEmpty() {
        #expect([AgeIdentity]().recipientsFile(includeNames: true).isEmpty)
    }
}
