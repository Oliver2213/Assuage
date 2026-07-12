import Foundation
import Testing
@testable import AssuageCore

@Suite("Post-quantum (X-Wing) identities")
struct PostQuantumTests {
    private let plaintext = Data("pqtest".utf8)

    /// A tagged hybrid post-quantum recipient produced by age-plugin-se
    /// (`keygen --pq --recipient-type tag`). Public material.
    static let tagpqRecipient = "age1tagpq184crw5lq3szxepnzm2x3rdpukekxws3394lc0x94qc8642negjxf44us2zjsxusk890yaps29ankhcntp2njx3hshg93g3dqt8mg7hveezwkwxhzwu4ykg30nem9cyekjjfdc2src72twryhfgsyusjxhmcse8hang6vc3xyuqj326pn4av2swmkuwesq0zu907vkqhzz68njx7kzyqau2wyeejj5j0ggyqppzprcyya40ppp7cy7yrv29qnwwqmtgw49rp5aljxvszsyfw5g9n9umrlkzyg7f2tsv3503j9x7s45at399r259t5q2ggs5als46eeg0spcdluhtsn7asjjwswchjf32ttv367x9cqfrv0fxcntqdjxptvec7afckagp4wpu7z28t3q2kvy6mpr46aaf3wnk62q064d2wfj6slaz9jc0f3rhh2umrv6ctxky6pvup9jrzjgpqrz3m558av53y7z2ufrfxry9mxkqhhv79tjem6w3kg2cmwylq5as0mjda5zrzfejf5luu0y5mv4p0ymr6ratle32c06gsrdx6z5e609wqdly8nd4rhzzxpxg04gruz960qck2kh5fkvs30qdf5n7tjw9tkaz2kev2jm4kfel0fg22k52cxx9wmsr6e3f30tvex2r0n3zqp8rjhmaq5wexqgn79qakdf9g94xxjngvy8qkyypsj2pmwdmh69cdk6pvfutkxkqg0wedasljufqhd92xh73r0tldju7l4d0uafznm3v9v6xng3gkjywyhf34meym89zt4pz25n04qf76xjcm8dta9efqffsg4lnyev5gewqj94gqk8wxk8gzs97rjvzqjydzv5z20532kuajjsary8ju4xznuap9m8a2syusfg50v80rxe80urrx2m99quzx2f3f0v8qf2qwlpu26zdcwcsp5le32m8le88995cmykvh795pnz7sqykp4d3wljex2rqhk846gdfw268kykgd85ya3lmc3tjr59663fn0g88hvfck3zmzfk830pqug89qwkg6mdez7xafn2qngaz4ezq6g58xcmqcngwzwwkkr6r8xrswwh8tkwf0c09gd92h5zz9c76zf3c4xfqttnyqkjemdnlth3g0hw58v0zetxz3xzcxdj33k820waq8q5u238jnqw49fuc6yzjltz2sn2zc54pcwahuy99zynf3jc7r4ds40au4f9y5pgpmej3769mms9faa0r97japgsjny2k0causnk6qnq43rvlk4tfc540825s626rnvgpye5fve5xvcc22xd2r4gmtntnvgwepgvmwq4t7cp9a2u3wrzuvpct8n69s4jh5ustjgydu5vj2vkn8jyksv3j7pvwkyzjqa0gt8jcqg37v9xemtzefgs3p4w2ehg9hznu8pyxk3p3kdvm56wj6ghd2e62zynmu9gswn5gkufvrd4m639turpt24yuw9u9nu77f49seypz520jxrdvd8j3rsx2hn82hk5e0rjzvhdw87afk3wzptmd4nzvegnfvssayzqylaz5f75wpq639gzgmxwt5qp599mafneh5d9ch9sscc8r0f7m72jsvddvjkpvnfvtypd5mcf5ua75me3murkascf5hj9jthv2n2656thjktqy5sx2vx4yq6nx2nran3psn060sk9mrkmrc2j53jncxth8vra70kscz7khk52jypj324re8rwnyjst3766fl3y8rfa3z4lszwckgn8mv7m7yuy05h96f322ynt5tgd08g7m3z9s6d5p8nwyphzvnxmr0dvytaukqwrztqxqvmm02lep5l9r9ryvpkt8gjru3yny0dqqddrxs3d3wxrdtk4tlruwmyk6alu263cy6sxhuvmp42nf2nm45sgrhtn3uth25selprzlq7e53ll0l7krpxt4zrp0lddark5vsahe3908emwtmsvzj5wcr4w28lp38dmh2a4uxqss90y4v"

    @Test("Generate, encrypt, and decrypt a post-quantum identity")
    func roundTrip() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum(label: "pq")
        #expect(identity.recipient.kind == .postQuantum)
        #expect(identity.recipient.encoding.hasPrefix("age1pq1"))

        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        let decrypted = try Cipher.decrypt(encrypted, with: [identity])
        #expect(decrypted == plaintext)
    }

    @Test("A post-quantum file is flagged as post-quantum by the inspector")
    func inspectionReportsPostQuantum() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        let info = try AgeFileInspector.inspect(encrypted)
        #expect(info.postQuantum == .yes)
        #expect(info.stanzaTypes.contains("mlkem768x25519"))
    }

    @Test("A recipient string parses back as post-quantum")
    func recipientParses() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let recipient = try AgeRecipient(parsing: identity.recipient.encoding)
        #expect(recipient.kind == .postQuantum)
        #expect(recipient.encoding == identity.recipient.encoding)
    }

    @Test("Encrypting to an age1tagpq (mlkem768p256tag) recipient makes a post-quantum file")
    func hardwareRecipientEncryptTo() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let recipient = try AgeRecipient(parsing: Self.tagpqRecipient)
        #expect(recipient.kind == .postQuantumHardware)

        let encrypted = try Cipher.encrypt(plaintext, to: [recipient])
        let info = try AgeFileInspector.inspect(encrypted)
        #expect(info.postQuantum == .yes)
        #expect(info.stanzaTypes.contains("mlkem768p256tag"))
    }

    @Test("An exported software post-quantum identity re-imports and decrypts")
    func softwarePostQuantumImportRoundTrips() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum(label: "pq")
        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])

        // The exported identity file re-imports to the same recipient…
        let imported = AgeIdentity.importableKeys(from: identity.ageFormatted())
        guard let key = imported.first(where: { $0.recipient.kind == .postQuantum }) else {
            Issue.record("exported X-Wing identity did not re-import as post-quantum")
            return
        }
        #expect(key.recipient.encoding == identity.recipient.encoding)

        // …and the committed identity decrypts a file made for it.
        let reimported = try AgeIdentity(importing: key, label: "pq", protection: .local)
        #expect(try Cipher.decrypt(encrypted, with: [reimported]) == plaintext)
    }

    @Test("A stranger's post-quantum identity does not decrypt the file")
    func wrongIdentityFails() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let identity = try AgeIdentity.generatePostQuantum()
        let stranger = try AgeIdentity.generatePostQuantum()
        let encrypted = try Cipher.encrypt(plaintext, to: [identity.recipient])
        #expect(throws: (any Error).self) {
            try Cipher.decrypt(encrypted, with: [stranger])
        }
    }

    /// Import an identity generated by age-plugin-se and confirm we derive the same
    /// `age1tagpq` recipient it advertises — proving our identity encoding matches
    /// theirs. Reconstruction + public key only, so no Touch ID prompt. Skipped
    /// unless the age-plugin-se binary is installed and the enclave does ML-KEM.
    @Test("An age-plugin-se post-quantum identity imports with the matching recipient")
    func importsAgePluginSeIdentity() throws {
        guard #available(macOS 26, iOS 26, *) else { return }
        let candidates = [
            "\(NSHomeDirectory())/src/age-plugin-se/.build/debug/age-plugin-se",
            "\(NSHomeDirectory())/src/age-plugin-se/.build/release/age-plugin-se",
            "/opt/homebrew/bin/age-plugin-se",
        ]
        guard let plugin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }

        let keyText = try runKeygen(plugin)
        guard let expected = keyText.split(whereSeparator: \.isNewline)
            .first(where: { $0.contains("public key (post-quantum):") })?
            .split(separator: " ").last.map(String.init) else {
            Issue.record("age-plugin-se produced no post-quantum recipient")
            return
        }

        let imported = AgeIdentity.importableKeys(from: keyText)
        guard let key = imported.first(where: { $0.recipient.kind == .postQuantumHardware }) else {
            Issue.record("age-plugin-se identity was not recognized as post-quantum on import")
            return
        }
        #expect(key.recipient.encoding == expected)
    }

    @Test("Our exported hardware post-quantum identity re-imports as post-quantum")
    func exportedHardwareIdentityRoundTrips() throws {
        guard #available(macOS 26, iOS 26, *), SecureEnclaveKeys.isAvailable else { return }
        let identity = try AgeIdentity.generateSecureEnclavePostQuantum(label: "pq-se")
        // ageFormatted writes the AGE-PLUGIN-SE- identity string we hand out.
        let reimported = AgeIdentity.importableKeys(from: identity.ageFormatted())
        guard let key = reimported.first(where: { $0.recipient.kind == .postQuantumHardware }) else {
            Issue.record("our exported hardware PQ identity did not re-import as post-quantum")
            return
        }
        #expect(key.recipient.encoding == identity.recipient.encoding)
    }

    private func runKeygen(_ plugin: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: plugin)
        proc.arguments = ["keygen", "--pq", "--recipient-type", "tag"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
