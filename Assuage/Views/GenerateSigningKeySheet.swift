import SwiftUI
import AssuageCore

/// Create a note-signing key: an Ed25519 signer bound to a name, used to sign text
/// in the signed-note format. Simpler than `GenerateKeySheet` — a signing key has
/// no algorithm or Secure Enclave choice, only a name and where its seed is stored.
struct GenerateSigningKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var storage: KeyStorage = .thisDevice
    @State private var keychainAuth: KeychainAuth = .biometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The spec allows any non-empty name without spaces or `+`; validate live so the
    /// button only enables for a name that will actually make a key.
    private var isNameValid: Bool { VerifierKey.isValidName(trimmedName) }
    private var keychainProtection: KeychainProtection { storage.keychainProtection(auth: keychainAuth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate Signing Key")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. “example.com/alice”"))
                    .help("Names your signatures. Any text without spaces or a “+”. A domain-style name (like example.com/alice) is recommended so others can tell whose key it is.")
                StoragePicker(storage: $storage, auth: $keychainAuth)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !trimmedName.isEmpty, !isNameValid {
                WarningLabel("A name can’t contain spaces or a “+”.")
            }
            if storage == .touchID, keychainAuth == .currentBiometry {
                CurrentBiometryWarning()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Generate", action: generate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isNameValid)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .alert("Couldn’t generate signing key", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// Explains the key kind and what the chosen storage means — the same
    /// no-surprises framing as the age generate sheet.
    private var explanation: LocalizedStringKey {
        switch storage {
        case .synced:
            "An Ed25519 **signing key** for signed notes, synced to your other devices via iCloud Keychain. Its public **verifier key** is what others use to check your signatures."
        case .thisDevice:
            "An Ed25519 **signing key** for signed notes, stored in your keychain on this Mac only. Its public **verifier key** is what others use to check your signatures."
        case .touchID:
            "An Ed25519 **signing key** for signed notes, wrapped by this Mac’s Secure Enclave — signing asks for Touch ID. Stays on this Mac (protected keys can’t sync)."
        case .secureEnclave:
            "" // not offered: an arbitrary Ed25519 seed can't be sealed in the enclave
        }
    }

    private func generate() {
        do {
            try model.generateSigningKey(name: trimmedName, protection: keychainProtection)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
