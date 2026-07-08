import SwiftUI
import CypherdexCore

struct GenerateKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum KeyType: String, CaseIterable, Identifiable {
        case x25519, secureEnclave
        var id: Self { self }
        var title: String {
            switch self {
            case .x25519: return "Keychain"
            case .secureEnclave: return "Secure Enclave"
            }
        }
    }

    @AppStorage(PreferenceKeys.defaultEnclaveAccessControl)
    private var defaultEnclaveAccessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode

    @State private var keyType: KeyType = .x25519
    @State private var label = ""
    @State private var storageMode: KeychainStorageMode = .authenticated
    @State private var keychainAuth: KeychainAuth = .biometryOrPasscode
    @State private var accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    /// The protection to create a keychain key with, from the current choices.
    private var keychainProtection: KeychainProtection {
        storageMode.protection(auth: keychainAuth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate age Keypair")
                .font(.title2.bold())

            Form {
                Picker("Key type", selection: $keyType) {
                    ForEach(KeyType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)

                TextField("Label", text: $label, prompt: Text("Optional, e.g. “My Laptop”"))

                switch keyType {
                case .x25519:
                    Picker("Storage", selection: $storageMode) {
                        ForEach(KeychainStorageMode.allCases) { Text($0.title).tag($0) }
                    }
                    if storageMode == .authenticated {
                        Picker("Require", selection: $keychainAuth) {
                            ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                case .secureEnclave:
                    Picker("Require to use", selection: $accessControl) {
                        ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                            Text(control.displayName).tag(control)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if keyType == .x25519, storageMode == .authenticated, keychainAuth == .currentBiometry {
                Label("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable. Export a backup if you'd want it back.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if keyType == .secureEnclave && !model.secureEnclaveAvailable {
                Label("This Mac doesn’t have a Secure Enclave.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyType == .secureEnclave && !model.secureEnclaveAvailable)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { accessControl = defaultEnclaveAccessControl }
        .alert("Couldn’t generate key", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var explanation: LocalizedStringKey {
        switch keyType {
        case .x25519:
            switch storageMode {
            case .authenticated:
                return "A standard age key, exportable and usable with any age tool. Its secret is wrapped by this Mac’s **Secure Enclave**, so it isn’t readable at rest — using or exporting it asks for Touch ID. Stays on this Mac (protected keys can’t sync)."
            case .local:
                return "A standard age key, stored in your keychain and kept on this Mac only. Readable whenever your keychain is unlocked. It can be exported and used with any age tool, on any machine."
            case .synced:
                return "A standard age key, stored in your keychain and synced to your other devices via iCloud Keychain. It can be exported and used with any age tool, on any machine."
            }
        case .secureEnclave:
            return "The key is sealed by this Mac’s **Secure Enclave**: you still hold the key and can export it for backup, but since it’s encrypted by the enclave it only works on the Mac that generated it. Compatible with age-plugin-se."
        }
    }

    private func generate() {
        do {
            switch keyType {
            case .x25519:
                try model.generateX25519(label: label, protection: keychainProtection)
            case .secureEnclave:
                try model.generateSecureEnclave(label: label, accessControl: accessControl)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
