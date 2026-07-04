import SwiftUI
import CypherdexCore

/// The app's Preferences window (⌘,). Presented from the `Settings` scene, so
/// macOS supplies the menu item and shortcut automatically.
struct SettingsView: View {
    @AppStorage(PreferenceKeys.defaultEnclaveAccessControl)
    private var defaultEnclaveAccessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @AppStorage(PreferenceKeys.exportAuthPolicy)
    private var exportAuthPolicy: ExportAuthPolicy = .always
    @AppStorage(PreferenceKeys.requireAuthToDelete)
    private var requireAuthToDelete = false

    var body: some View {
        Form {
            Section {
                Picker("Default protection for new keys", selection: $defaultEnclaveAccessControl) {
                    ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                        Text(control.displayName).tag(control)
                    }
                }
            } header: {
                Text("Secure Enclave")
            } footer: {
                Text("The presence policy a new Secure Enclave key is created with. You can still override it per key when generating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Require Touch ID to export a key", selection: $exportAuthPolicy) {
                    ForEach(ExportAuthPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Toggle("Require Touch ID to delete a key", isOn: $requireAuthToDelete)
            } header: {
                Text("Authentication")
            } footer: {
                Text("These prompts deter casual access on an unlocked Mac — they don’t encrypt the key at rest, so a keychain key can still be read by any tool with keychain access. For a key that must stay on this Mac and require Touch ID cryptographically, generate a Secure Enclave key instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 340)
    }
}

#Preview {
    SettingsView()
}
