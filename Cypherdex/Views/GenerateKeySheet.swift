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
            case .x25519: return "Software (X25519)"
            case .secureEnclave: return "Secure Enclave"
            }
        }
    }

    @State private var keyType: KeyType = .x25519
    @State private var label = ""
    @State private var accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate age Keypair")
                .font(.title2.bold())

            Picker("Key type", selection: $keyType) {
                ForEach(KeyType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Label", text: $label, prompt: Text("Optional, e.g. “My Laptop”"))

                if keyType == .secureEnclave {
                    Picker("Require to use", selection: $accessControl) {
                        ForEach(SecureEnclaveAccessControl.allCases, id: \.self) { control in
                            Text(control.displayName).tag(control)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: keyType == .secureEnclave ? 100 : 60)

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
        .frame(width: 440)
        .alert("Couldn’t generate key", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var explanation: LocalizedStringKey {
        switch keyType {
        case .x25519:
            return "A standard age key. The private key is held by the app for this session — **export it to keep it**. Works with any age tool."
        case .secureEnclave:
            return "The private key is generated inside this Mac’s **Secure Enclave** and can never be exported. Compatible with age-plugin-se."
        }
    }

    private func generate() {
        do {
            switch keyType {
            case .x25519:
                model.generateX25519(label: label)
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
