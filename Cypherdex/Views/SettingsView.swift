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
    @AppStorage(PreferenceKeys.clipboardConcealMarker)
    private var clipboardConcealMarker = true
    @AppStorage(PreferenceKeys.clipboardClearAfterCopy)
    private var clipboardClearAfterCopy = false
    @AppStorage(PreferenceKeys.clipboardClearDelay)
    private var clipboardClearDelay = 30
    @AppStorage(PreferenceKeys.clipboardProtectAllCopies)
    private var clipboardProtectAllCopies = false
    @AppStorage(PreferenceKeys.allowClipboardExport)
    private var allowClipboardExport = false

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

            Section {
                Toggle("Mark copies as concealed", isOn: $clipboardConcealMarker)
                Toggle("Clear the clipboard after copying", isOn: $clipboardClearAfterCopy)
                Stepper(value: $clipboardClearDelay, in: 5...300, step: 5) {
                    Text("Clear after ^[\(clipboardClearDelay) second](inflect: true)")
                }
                .disabled(!clipboardClearAfterCopy)
                Toggle("Protect all copies, including public keys", isOn: $clipboardProtectAllCopies)
                Toggle("Allow exporting a private key to the clipboard", isOn: $allowClipboardExport)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("“Concealed” asks clipboard managers to treat a copy as confidential and not store it — a best-effort signal, not a guaranteed block on Handoff / Universal Clipboard, which AppKit can’t offer. Auto-clear is the reliable safeguard: it wipes the clipboard after the delay unless you’ve copied something else. By default these apply only to sensitive text (decrypted output); turn on “Protect all copies” to include public keys and encrypted output too. Exporting a private key to the clipboard is off by default because it puts key material on the clipboard.")
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
