import SwiftUI
import AssuageCore

/// The General tab of Settings: authentication gates, new-key defaults, and about.
struct GeneralSettingsView: View {
    @AppStorage(PreferenceKeys.exportAuthPolicy)
    private var exportAuthPolicy: ExportAuthPolicy = .always
    @AppStorage(PreferenceKeys.requireAuthToDelete)
    private var requireAuthToDelete = false
    @AppStorage(PreferenceKeys.confirmTouchIDBeforeEncrypt)
    private var confirmTouchIDBeforeEncrypt = false
    @AppStorage(PreferenceKeys.defaultEnclaveAccessControl)
    private var defaultEnclaveAccessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @AppStorage(PreferenceKeys.defaultKeyType)
    private var defaultKeyType: DefaultKeyType = .standard
    @AppStorage(PreferenceKeys.publicKeyDisplay)
    private var publicKeyDisplay: PublicKeyDisplay = .abbreviated
    @AppStorage(PreferenceKeys.defaultSigningIdentities)
    private var defaultSigningIdentities: DefaultSigningIdentities = .all
    @AppStorage(PreferenceKeys.defaultKeyStorage)
    private var defaultKeyStorage: KeyStorage = .touchID

    var body: some View {
        Form {
            Section {
                Picker("Show public keys as", selection: $publicKeyDisplay) {
                    ForEach(PublicKeyDisplay.allCases) { Text($0.title).tag($0) }
                }
                .help("How public keys appear in lists. Copying or exporting always uses the full key.")
            } header: {
                Text("Display")
            }

            Section {
                Picker("Require Touch ID to export a key", selection: $exportAuthPolicy) {
                    ForEach(ExportAuthPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .help("Whether exporting a key’s secret asks for Touch ID first.")
                Toggle("Require Touch ID to delete a key", isOn: $requireAuthToDelete)
                    .help("Ask for Touch ID before deleting a key.")
                Toggle("Confirm with Touch ID before encrypting", isOn: $confirmTouchIDBeforeEncrypt)
                    .help("Ask for Touch ID before encrypting. A convenience gate — encryption needs no secret.")
            } header: {
                Text("Authentication")
            } footer: {
                Text("Touch ID here is a convenience gate on an unlocked Mac — it confirms intent but doesn’t encrypt anything, so a keychain key stays readable by any tool with keychain access.\n\nFor real protection at rest, generate a **Secure Enclave** key: its private key is created inside Apple’s Secure Enclave and never leaves the chip, so it can only be used with Touch ID — enforced by the hardware, not by these settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                // Post-quantum types only exist on macOS 26+, so only offer the
                // type default there.
                if #available(macOS 26, *) {
                    Picker("New keys", selection: $defaultKeyType) {
                        ForEach(DefaultKeyType.allCases) { Text($0.title).tag($0) }
                    }
                    .help("The type new keys start on. You can still switch per key when generating.")
                }
                Picker("Protection for new keys", selection: $defaultKeyStorage) {
                    ForEach(KeyStorage.keychainCases) { Text($0.title).tag($0) }
                }
                .help("Where a new keychain-backed key (age, post-quantum, SSH) is stored and how it’s guarded.")
                Picker("Protection for new Secure Enclave keys", selection: $defaultEnclaveAccessControl) {
                    ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                        Text(control.displayName).tag(control)
                    }
                }
                .help("The presence policy a new Secure Enclave key is created with.")
                Picker("Sign notes with", selection: $defaultSigningIdentities) {
                    ForEach(DefaultSigningIdentities.allCases) { Text($0.title).tag($0) }
                }
                .help("Which note signing keys to sign with by default.")
            } header: {
                Text("Defaults")
            } footer: {
                Text("Starting points for new keys and signing — you can still customize each per key when generating, or per note when signing. **Protection for new keys** covers keychain keys (age, post-quantum, SSH); Secure Enclave keys use their own presence policy. **Sign notes with** also sets which keys the **Sign Note with \(AppInfo.name)** service uses.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("Install source", value: AppInfo.distribution.displayName)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }
}
