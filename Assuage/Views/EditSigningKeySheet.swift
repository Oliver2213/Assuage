import SwiftUI
import AssuageCore

/// Edit a signing key's storage (This device / Synced / Touch ID). The name is
/// bound into the key's identity — changing it would produce a different verifier
/// key that no longer matches signatures already made — so it's shown read-only.
struct EditSigningKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let signer: SigningKey
    @State private var storage: KeyStorage
    @State private var keychainAuth: KeychainAuth
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    init(signer: SigningKey) {
        self.signer = signer
        _storage = State(initialValue: KeyStorage(keychainProtection: signer.protection) ?? .thisDevice)
        if case .authenticated(let auth) = signer.protection {
            _keychainAuth = State(initialValue: auth)
        } else {
            _keychainAuth = State(initialValue: .biometryOrPasscode)
        }
    }

    private var currentlyAuthenticated: Bool { signer.protection.requiresAuthentication }
    private var newProtection: KeychainProtection { storage.keychainProtection(auth: keychainAuth) }
    private var hasChanges: Bool { newProtection != signer.protection }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Signing Key")
                .font(.title2.bold())

            Form {
                LabeledContent("Name", value: signer.name)
                LabeledContent("Verifier key") {
                    Text(signer.verifierKeyEncoding)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Key ID", value: signer.keyIDHex)

                StoragePicker(storage: $storage, auth: $keychainAuth)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isSaving)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if storage == .touchID, keychainAuth == .currentBiometry {
                CurrentBiometryWarning()
            } else if currentlyAuthenticated, hasChanges {
                Text("Changing a Touch ID–protected key’s storage asks for Touch ID to unlock its seed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isSaving)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .alert("Couldn’t save changes", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var explanation: LocalizedStringKey {
        switch storage {
        case .synced:
            "Synced to your other devices via iCloud Keychain."
        case .thisDevice:
            "Stored in your keychain on this Mac only."
        case .touchID:
            "Wrapped by this Mac’s Secure Enclave, so signing asks for Touch ID. Stays on this Mac (protected keys can’t sync)."
        case .secureEnclave:
            ""
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await model.changeSignerProtection(of: signer, to: newProtection)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
                isSaving = false
            }
        }
    }
}
