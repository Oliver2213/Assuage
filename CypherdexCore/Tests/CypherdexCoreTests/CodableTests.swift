import Foundation
import Testing
@testable import CypherdexCore

@Suite("Codable persistence")
struct CodableTests {

    @Test("X25519 identity round-trips through JSON")
    func x25519RoundTrip() throws {
        let original = AgeIdentity.generateX25519(label: "Persisted")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AgeIdentity.self, from: data)

        #expect(restored.id == original.id)
        #expect(restored.label == original.label)
        #expect(restored.recipient == original.recipient)
        #expect(restored.material == original.material)
        #expect(restored.source == original.source)
    }

    @Test("Sync flag round-trips and drives the source")
    func syncFlagRoundTrip() throws {
        let generated = AgeIdentity.generateX25519()
        guard case .x25519(let secret, _) = generated.material else {
            Issue.record("expected x25519 material"); return
        }
        let synced = try AgeIdentity(importingX25519: secret, label: "Laptop", synced: true)
        #expect(synced.isSynced)
        #expect(synced.source == .keychain(synced: true))

        let restored = try JSONDecoder().decode(AgeIdentity.self, from: JSONEncoder().encode(synced))
        #expect(restored.isSynced)
        #expect(restored.source == .keychain(synced: true))

        let local = AgeIdentity.generateX25519(synced: false)
        #expect(!local.isSynced)
        #expect(local.source == .keychain(synced: false))
    }

    @Test("Secure Enclave material round-trips with its access control")
    func secureEnclaveMaterialRoundTrip() throws {
        // Construct SE material directly (no hardware needed) to exercise Codable.
        let material = IdentityMaterial.secureEnclave(
            identity: "AGE-PLUGIN-SE-1EXAMPLE",
            accessControl: .anyBiometryAndPasscode
        )
        let data = try JSONEncoder().encode(material)
        let restored = try JSONDecoder().decode(IdentityMaterial.self, from: data)
        #expect(restored == material)
    }
}
