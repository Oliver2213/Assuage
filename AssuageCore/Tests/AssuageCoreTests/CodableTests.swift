import Foundation
import Testing
@testable import AssuageCore

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

    @Test("Protection round-trips and drives sync + presence")
    func protectionRoundTrip() throws {
        let generated = AgeIdentity.generateX25519()
        guard case .x25519(let secret, _) = generated.material else {
            Issue.record("expected x25519 material"); return
        }
        let synced = try AgeIdentity(importingX25519: secret, label: "Laptop", protection: .synced)
        #expect(synced.isSynced)
        #expect(synced.source == .keychain(synced: true))

        let restored = try JSONDecoder().decode(AgeIdentity.self, from: JSONEncoder().encode(synced))
        #expect(restored.isSynced)
        #expect(restored.source == .keychain(synced: true))
        #expect(restored.keychainProtection == .synced)

        let local = AgeIdentity.generateX25519(protection: .local)
        #expect(!local.isSynced)
        #expect(!local.requiresPresence)
        #expect(local.source == .keychain(synced: false))

        let protected = AgeIdentity.generateX25519(protection: .authenticated(.currentBiometry))
        #expect(!protected.isSynced)
        #expect(protected.requiresPresence)
        #expect(protected.keychainProtection == .authenticated(.currentBiometry))
        let restoredProtected = try JSONDecoder().decode(AgeIdentity.self, from: JSONEncoder().encode(protected))
        #expect(restoredProtected.keychainProtection == .authenticated(.currentBiometry))
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
