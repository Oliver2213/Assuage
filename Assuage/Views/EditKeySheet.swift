import SwiftUI
import AssuageCore

/// Edit an existing key: rename it, and for keychain (X25519 / X-Wing / SSH) keys
/// move it between synced / this-device / Touch ID storage. Secure Enclave keys are
/// sealed to this Mac, so only their label can change. Mirrors `GenerateKeySheet`'s
/// storage ladder and explanation so the two key sheets read the same.
struct EditKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let identity: AgeIdentity
    @State private var label: String
    @State private var storage: KeyStorage
    @State private var keychainAuth: KeychainAuth
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    init(identity: AgeIdentity) {
        self.identity = identity
        _label = State(initialValue: identity.label)
        _storage = State(initialValue: KeyStorage(keychainProtection: identity.keychainProtection) ?? .touchID)
        if case .authenticated(let auth) = identity.keychainProtection {
            _keychainAuth = State(initialValue: auth)
        } else {
            _keychainAuth = State(initialValue: .biometryOrPasscode)
        }
    }

    /// True for keychain keys (storage is editable); false for Secure Enclave.
    private var isKeychainKey: Bool { identity.keychainProtection != nil }
    private var currentlyAuthenticated: Bool { identity.keychainProtection?.requiresAuthentication ?? false }
    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var labelChanged: Bool { trimmedLabel != identity.label }

    private var newProtection: KeychainProtection { storage.keychainProtection(auth: keychainAuth) }
    private var protectionChanged: Bool {
        isKeychainKey && newProtection != identity.keychainProtection
    }
    private var hasChanges: Bool { labelChanged || protectionChanged }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Key")
                .font(.title2.bold())

            Form {
                TextField("Label", text: $label, prompt: Text(identity.defaultName))
                LabeledContent("Type", value: identity.kindDescription)
                LabeledContent("Public key") {
                    Text(identity.recipient.encoding)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if isKeychainKey {
                    StoragePicker(storage: $storage, auth: $keychainAuth)
                } else {
                    LabeledContent("Storage", value: identity.sourceDescription)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isSaving)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isKeychainKey, storage == .touchID, keychainAuth == .currentBiometry {
                CurrentBiometryWarning()
            } else if currentlyAuthenticated, protectionChanged {
                Text("Changing a Touch ID–protected key’s storage asks for Touch ID to unlock its secret.")
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

    /// Names the key's kind and what its (possibly changed) storage means — the same
    /// no-surprises framing as the generate sheet, adapted to an existing key.
    private var explanation: LocalizedStringKey {
        let kind = identity.kindDescription
        guard isKeychainKey else {
            return "\(kind) — sealed to the Mac that generated it, so it can’t be moved or synced. You can export it for backup, but only its label can change here."
        }
        switch storage {
        case .synced:
            return "\(kind) — synced to your other devices via iCloud Keychain."
        case .thisDevice:
            return "\(kind) — stored in your keychain on this Mac only."
        case .touchID:
            return "\(kind) — wrapped by this Mac’s Secure Enclave, so using or exporting it asks for Touch ID. Stays on this Mac (protected keys can’t sync)."
        case .secureEnclave:
            return "" // not reachable: enclave keys aren't keychain keys
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                if protectionChanged {
                    try await model.changeProtection(of: identity, to: newProtection, newLabel: label)
                } else if labelChanged {
                    try model.rename(identity, to: label)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
                isSaving = false
            }
        }
    }
}
