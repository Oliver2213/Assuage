import SwiftUI
import AssuageCore

struct GenerateKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PreferenceKeys.defaultEnclaveAccessControl)
    private var defaultEnclaveAccessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @AppStorage(PreferenceKeys.defaultToPostQuantum)
    private var defaultToPostQuantum = false

    @State private var isPostQuantum = false
    @State private var storage: KeyStorage = .touchID
    @State private var label = ""
    @State private var keychainAuth: KeychainAuth = .biometryOrPasscode
    @State private var accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    /// Storage rows offered. All apply to both algorithms: a keychain key is
    /// X25519 or X-Wing, and the Secure Enclave row is P-256 or (post-quantum)
    /// ML-KEM-768 + P-256.
    private var availableStorage: [KeyStorage] { KeyStorage.allCases }

    /// The keychain protection for the non-enclave rows.
    private var keychainProtection: KeychainProtection { storage.keychainProtection(auth: keychainAuth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate age Keypair")
                .font(.title2.bold())

            Form {
                if #available(macOS 26, *) {
                    Picker("Type", selection: $isPostQuantum) {
                        Text("Standard").tag(false)
                        Text("Post-quantum").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Label", text: $label, prompt: Text("Optional, e.g. “My Laptop”"))

                Picker("Storage", selection: $storage) {
                    ForEach(availableStorage) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)

                switch storage {
                case .touchID:
                    Picker("Require", selection: $keychainAuth) {
                        ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
                    }
                case .secureEnclave:
                    Picker("Require", selection: $accessControl) {
                        ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                            Text(control.displayName).tag(control)
                        }
                    }
                case .synced, .thisDevice:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if storage == .touchID, keychainAuth == .currentBiometry {
                WarningLabel("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable. Export a backup if you'd want it back.")
            }
            if storage == .secureEnclave, !model.secureEnclaveAvailable {
                WarningLabel("This Mac doesn’t have a Secure Enclave.")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Generate", action: generate)
                    .buttonStyle(.borderedProminent)
                    .disabled(storage == .secureEnclave && !model.secureEnclaveAvailable)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            accessControl = defaultEnclaveAccessControl
            // Post-quantum requires macOS 26; the pref is only settable there, but
            // guard anyway so a stale value can't select an unavailable type.
            if #available(macOS 26, *) { isPostQuantum = defaultToPostQuantum }
        }
        .alert("Couldn’t generate key", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// Names the exact key kind (curve/algorithm in parentheses) and what the
    /// chosen storage means — so nothing about the resulting key is hidden.
    private var explanation: LocalizedStringKey {
        switch storage {
        case .secureEnclave:
            return isPostQuantum
                ? "A **Secure Enclave** post-quantum key (ML-KEM-768 + P-256): quantum-secure, with both private keys sealed inside this Mac’s enclave. Only works on the Mac that generated it; wire-compatible with age-plugin-se."
                : "A **Secure Enclave** key (P-256): sealed by this Mac’s enclave, so you still hold it and can export it for backup, but it only works on the Mac that generated it. Compatible with age-plugin-se."
        case .synced:
            return isPostQuantum
                ? "A post-quantum key (X-Wing), synced to your other devices via iCloud Keychain. Exportable and usable with age 1.3 or later."
                : "A standard age key (X25519), synced to your other devices via iCloud Keychain. Exportable and usable with any age tool."
        case .thisDevice:
            return isPostQuantum
                ? "A post-quantum key (X-Wing), stored in your keychain on this Mac only. Exportable and usable with age 1.3 or later."
                : "A standard age key (X25519), stored in your keychain on this Mac only. Readable whenever your keychain is unlocked; exportable and usable with any age tool."
        case .touchID:
            return isPostQuantum
                ? "A post-quantum key (X-Wing), wrapped by this Mac’s **Secure Enclave** — using or exporting it asks for Touch ID. Stays on this Mac (protected keys can’t sync). Usable with age 1.3 or later."
                : "A standard age key (X25519), wrapped by this Mac’s **Secure Enclave** — using or exporting it asks for Touch ID. Stays on this Mac (protected keys can’t sync). Usable with any age tool."
        }
    }

    private func generate() {
        do {
            switch storage {
            case .secureEnclave:
                if isPostQuantum {
                    guard #available(macOS 26, *) else { return }
                    try model.generateSecureEnclavePostQuantum(label: label, accessControl: accessControl)
                } else {
                    try model.generateSecureEnclave(label: label, accessControl: accessControl)
                }
            case .synced, .thisDevice, .touchID:
                if isPostQuantum {
                    guard #available(macOS 26, *) else { return }
                    try model.generatePostQuantum(label: label, protection: keychainProtection)
                } else {
                    try model.generateX25519(label: label, protection: keychainProtection)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
