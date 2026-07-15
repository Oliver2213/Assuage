import Foundation
import Testing
@testable import AssuageCore

/// The contact-card key convention: `<kind>:<percent-encoded key>`, round-tripping
/// age recipients, SSH recipients, and note verifier keys through a URL-safe value.
@Suite("Contact key field")
struct ContactKeyFieldTests {
    @Test("An age recipient round-trips and stays human-readable")
    func ageRoundTrip() {
        let recipient = AgeIdentity.generateX25519().recipient
        let (label, value) = ContactKeyField.entry(for: recipient)
        #expect(label == "age-public-key")
        // bech32 is all-unreserved, so the key is embedded verbatim.
        #expect(value == "age-public-key:\(recipient.encoding)")
        #expect(ContactKeyField.decode(value: value) == .recipient(recipient))
    }

    @Test("An SSH recipient round-trips and is URL-safe")
    func sshRoundTrip() throws {
        let ssh = try AgeRecipient(parsing: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA31YVvFNTIcaUhzeS+N33UOBnSPEYnM3CJ4k/S+yVg9 me@host")
        let (label, value) = ContactKeyField.entry(for: ssh)
        #expect(label == "ssh-public-key")
        // The space and base64 +/ must be encoded away.
        #expect(!value.contains(" "))
        #expect(!value.contains("+"))
        #expect(!value.contains("/"))
        #expect(ContactKeyField.decode(value: value) == .recipient(ssh))
    }

    @Test("A verifier key round-trips and is URL-safe")
    func verifierRoundTrip() throws {
        let verifier = try SigningIdentity.generate(name: "example.com/bob").verifierKey
        let (label, value) = ContactKeyField.entry(for: verifier)
        #expect(label == "verifier-key")
        #expect(!value.contains("+"))
        #expect(!value.contains("/"))
        #expect(ContactKeyField.decode(value: value) == .verifier(verifier))
    }

    @Test("A post-quantum recipient round-trips under age-public-key")
    func postQuantumRoundTrip() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let recipient = try AgeIdentity.generatePostQuantum().recipient
        let (label, value) = ContactKeyField.entry(for: recipient)
        #expect(label == "age-public-key")
        #expect(ContactKeyField.decode(value: value) == .recipient(recipient))
    }

    @Test("Non-key values don't decode", arguments: [
        "https://github.com/octocat",   // a real URL — not ours
        "mailto:someone@example.com",   // a different scheme
        "no-colon-at-all",
        "age-public-key:not-a-real-key" // our scheme, but the payload isn't a key
    ])
    func nonKeyValues(value: String) {
        #expect(ContactKeyField.decode(value: value) == nil)
    }

    @Test("parse routes raw pasted keys to recipient or verifier")
    func parseRawKeys() throws {
        let age = AgeIdentity.generateX25519().recipient
        #expect(ContactKeyField.parse(age.encoding) == .recipient(age))

        let ssh = try AgeRecipient(parsing: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA31YVvFNTIcaUhzeS+N33UOBnSPEYnM3CJ4k/S+yVg9 me@host")
        // Leading/trailing whitespace is tolerated.
        #expect(ContactKeyField.parse("  \(ssh.encoding)\n") == .recipient(ssh))

        let verifier = try SigningIdentity.generate(name: "example.com/bob").verifierKey
        #expect(ContactKeyField.parse(verifier.encoded) == .verifier(verifier))

        #expect(ContactKeyField.parse("not a key") == nil)
        #expect(ContactKeyField.parse("   ") == nil)
    }

    @Test("Our own key labels are recognized, others aren't")
    func labelRecognition() {
        #expect(ContactKeyField.isKeyLabel("age-public-key"))
        #expect(ContactKeyField.isKeyLabel("verifier-key"))
        #expect(!ContactKeyField.isKeyLabel("home"))
        #expect(!ContactKeyField.isKeyLabel("_$!<HomePage>!$_"))
    }

    @Test("Revocation-list labels map to their kind, others don't")
    func revocationLabels() {
        #expect(ContactRevocationField(label: "revoked-age-keys-url") == .age)
        #expect(ContactRevocationField(label: "revoked-ssh-keys-url") == .ssh)
        #expect(ContactRevocationField(label: "revoked-verifier-keys-url") == .verifier)
        #expect(ContactRevocationField(label: "home") == nil)
        // A revocation label is never one of our key-field labels, and vice versa.
        for field in ContactRevocationField.allCases {
            #expect(!ContactKeyField.isKeyLabel(field.label))
        }
    }
}
