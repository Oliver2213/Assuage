import Testing
@testable import AssuageCore

/// Parsing the `# access control:` label age-plugin-se writes. Pure value logic,
/// so it runs everywhere (no Secure Enclave hardware needed).
@Suite("Secure Enclave access-control labels")
struct AccessControlLabelTests {

    @Test("Every label round-trips through its age wording")
    func roundTrip() {
        for control in SecureEnclaveAccessControl.allCases {
            #expect(SecureEnclaveAccessControl(ageLabel: control.ageLabel) == control)
        }
    }

    @Test("Known age-plugin-se wordings parse")
    func knownWordings() {
        #expect(SecureEnclaveAccessControl(ageLabel: "none") == SecureEnclaveAccessControl.none)
        #expect(SecureEnclaveAccessControl(ageLabel: "any biometry") == .anyBiometry)
        #expect(SecureEnclaveAccessControl(ageLabel: "any biometry or passcode") == .anyBiometryOrPasscode)
        #expect(SecureEnclaveAccessControl(ageLabel: "current biometry and passcode") == .currentBiometryAndPasscode)
        // Surrounding whitespace and case are tolerated (comments vary).
        #expect(SecureEnclaveAccessControl(ageLabel: "  Any Biometry  ") == .anyBiometry)
    }

    @Test("Unknown wording is rejected")
    func unknownWording() {
        #expect(SecureEnclaveAccessControl(ageLabel: "quantum aura") == nil)
        #expect(SecureEnclaveAccessControl(ageLabel: "") == nil)
    }
}
