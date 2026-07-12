import SwiftUI

/// The Clipboard tab of Settings: clipboard protections, plus the recipients-file
/// naming toggle (which governs what lands on the clipboard when you copy recipients).
struct ClipboardSettingsView: View {
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
    @AppStorage(PreferenceKeys.recipientCommentLabels)
    private var recipientCommentLabels = false

    var body: some View {
        Form {
            Section {
                Toggle("Mark copies as concealed", isOn: $clipboardConcealMarker)
                    .help("Signals to clipboard managers that copied text from this app is confidential.")
                Toggle("Clear the clipboard after copying", isOn: $clipboardClearAfterCopy)
                    .help("Wipes the clipboard a set time after copying, unless you’ve copied something else since.")
                Stepper(value: $clipboardClearDelay, in: 5...300, step: 5) {
                    Text("Clear after ^[\(clipboardClearDelay) second](inflect: true)")
                }
                .disabled(!clipboardClearAfterCopy)
                .help("How long to wait before clearing the clipboard.")
                Toggle("Protect all copies, including public keys", isOn: $clipboardProtectAllCopies)
                    .help("Marks public keys / recipients as confidential as well.")
                Toggle("Allow exporting a private key to the clipboard", isOn: $allowClipboardExport)
                    .help("Allows private keys / identities to be copied to the clipboard instead of only written to a file.")
            } header: {
                Text("Clipboard")
            } footer: {
                Text("“Concealed” asks clipboard managers to treat a copy as confidential and not store it — a best-effort signal, not a guaranteed block on Handoff / Universal Clipboard, which AppKit can’t offer. Auto-clear is the reliable safeguard: it wipes the clipboard after the delay unless you’ve copied something else. By default these apply only to sensitive text (decrypted output and identities); turn on “Protect all copies” to include public keys and encrypted output too. Exporting a private key to the clipboard is off by default because it puts key material on the clipboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Include key names as comments", isOn: $recipientCommentLabels)
                    .help("Precede each public key in a copied or exported recipients file with a “# name” comment.")
            } header: {
                Text("Recipients")
            } footer: {
                Text("When you copy or export a **recipients** file, precede each public key with a “# name” comment. Off by default — just the recipients, one per line, which age reads and \(AppInfo.name) re-imports either way. This applies to recipients files only, not to exporting an individual identity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
