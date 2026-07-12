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
    @AppStorage(PreferenceKeys.defaultToPostQuantum)
    private var defaultToPostQuantum = false

    var body: some View {
        Form {
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

            // Post-quantum only exists on macOS 26+, so only offer the default there.
            if #available(macOS 26, *) {
                Section {
                    Toggle("Default new keys to post-quantum", isOn: $defaultToPostQuantum)
                        .help("New keys start on the post-quantum type. You can still switch per key when generating.")
                } header: {
                    Text("Post-Quantum")
                } footer: {
                    Text("When on, new keys start on the post-quantum type (X-Wing / ML-KEM); you can still switch per key when generating. Post-quantum keys require macOS 26 to create, and recipients need age 1.3 or later (or another up-to-date age tool) to use them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Default protection for new keys", selection: $defaultEnclaveAccessControl) {
                    ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                        Text(control.displayName).tag(control)
                    }
                }
                .help("The presence policy new Secure Enclave keys are created with.")
            } header: {
                Text("Secure Enclave")
            } footer: {
                Text("The presence policy a new Secure Enclave key is created with. You can still override it per key when generating.")
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
