import SwiftUI
import CypherdexCore

/// Edit an existing key: rename it, and for keychain (X25519) keys move it between
/// local / iCloud / Touch ID storage. Secure Enclave keys are sealed to this Mac,
/// so only their label can change.
struct EditKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let identity: AgeIdentity
    @State private var label: String
    @State private var storageMode: KeychainStorageMode
    @State private var keychainAuth: KeychainAuth
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    init(identity: AgeIdentity) {
        self.identity = identity
        _label = State(initialValue: identity.label)
        switch identity.keychainProtection {
        case .authenticated(let auth):
            _storageMode = State(initialValue: .authenticated)
            _keychainAuth = State(initialValue: auth)
        case .synced:
            _storageMode = State(initialValue: .synced)
            _keychainAuth = State(initialValue: .biometryOrPasscode)
        case .local, .none:
            _storageMode = State(initialValue: .local)
            _keychainAuth = State(initialValue: .biometryOrPasscode)
        }
    }

    /// True for X25519 keychain keys (storage is editable); false for Secure Enclave.
    private var isKeychainKey: Bool { identity.keychainProtection != nil }
    private var currentlyAuthenticated: Bool { identity.keychainProtection?.requiresAuthentication ?? false }
    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var labelChanged: Bool { trimmedLabel != identity.label }

    private var newProtection: KeychainProtection { storageMode.protection(auth: keychainAuth) }
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
                LabeledContent("Public key") {
                    Text(identity.recipient.encoding)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if isKeychainKey {
                    Picker("Storage", selection: $storageMode) {
                        ForEach(KeychainStorageMode.allCases) { Text($0.title).tag($0) }
                    }
                    if storageMode == .authenticated {
                        Picker("Require", selection: $keychainAuth) {
                            ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                } else {
                    LabeledContent("Storage", value: identity.sourceDescription)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isSaving)

            if !isKeychainKey {
                Text("Secure Enclave keys are sealed to this Mac — they can’t be moved to the keychain or re-protected, so only the label can change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if storageMode == .authenticated, keychainAuth == .currentBiometry {
                Label("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 440)
        .alert("Couldn’t save changes", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
