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
    @State private var syncToICloud = false
    @State private var accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

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
                    Toggle("Sync to my other devices", isOn: $syncToICloud)
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
            return syncToICloud
                ? "A standard age key, stored in your keychain and synced to your other devices via iCloud Keychain. It can be exported and used with any age tool, on any machine."
                : "A standard age key, stored in your keychain and kept on this Mac only. It can be exported and used with any age tool, on any machine."
        case .secureEnclave:
            return "The key is sealed by this Mac’s **Secure Enclave**: you still hold the key and can export it for backup, but since it’s encrypted by the enclave it only works on the Mac that generated it. Compatible with age-plugin-se."
        }
    }

    private func generate() {
        do {
            switch keyType {
            case .x25519:
                try model.generateX25519(label: label, synced: syncToICloud)
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
