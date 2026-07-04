import Foundation
import Testing
@testable import CypherdexCore

/// Real age/rage inserts a random-length "grease" stanza into every header, and
/// wraps any base64 body over 48 bytes across multiple 64-column lines. The header
/// MAC is computed over that wrapped, canonical encoding. This is a fixed vector
/// captured from `rage` whose grease body spans three lines, so it deterministically
/// exercises multi-line body handling on decrypt — the live interop tests only hit
/// it on the random runs where rage's grease happens to be long.
@Suite("Grease / multi-line stanza interop")
struct GreaseInteropTests {

    // Produced by `rage -r <recipient>` for the identity below; plaintext is
    // "age interop regression vector". Its `*-grease` stanza has a 3-line body.
    static let secretKey = "AGE-SECRET-KEY-1JZ8D9MZEFEU8WUFDXZWEMSYLG40SLPN5YK5RRFLMJEU4WRZLTVASLFWH03"
    static let ciphertextBase64 = """
        YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSA0ZFJTdzVSOTM2blN1Vi9xc2hTRlRRYUlmbW01\
        dTJVQVhYVzVhNTJ3SmxzCmtUOGhlWGluS2YzNXY4TkV2NHVraXpxOXQ0SDlwUVNEbzlrS1ZaS21sN0kK\
        LT4gZVJadVd4Ry1ncmVhc2UKaVZDRTZNTEZucDZrMU9vNGxnUmVxUjg4TGViTFQrNktNNmQ0MFZ2YU1y\
        aUp3UnR2VlZQajdVVVAwRERaVXlRYgp2THFONTEwdEtGOE43SFJQUndTcTVhL3dZT09Qb2pjL1RTMDVP\
        aWR1eGJldFo3cUFnL0pFSXl6Q0NxUHBsMW54CjdLWQotLS0gUHAvL0wyWERXOEJlYUZSK1JCaUs4WGli\
        TlhEcFpJZWs1SW9mM3RXSEk5WQqzQYVEeqof9G/A3RBbkidK/5WWq29/is0KrZJ+uxU0TuOEowun1E2e\
        ZHFVxgxtEe1V8y21lh3pc0ktSNf/
        """

    @Test("A rage file with a multi-line grease body decrypts")
    func multiLineGreaseDecrypts() throws {
        let cipher = try #require(Data(base64Encoded: Self.ciphertextBase64))
        let identity = try AgeIdentity(importingX25519: Self.secretKey)
        let plaintext = try Cipher.decrypt(cipher, with: [identity])
        #expect(String(decoding: plaintext, as: UTF8.self) == "age interop regression vector")
    }
}
