import SwiftUI
import AssuageCore

struct GenerateKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Where a key lives and how it's guarded — one ordered ladder from most
    /// portable to most locked-down. The underlying algorithm is derived rather
    /// than chosen: the keychain rows are X25519 (or X-Wing when post-quantum),
    /// and the Secure Enclave row is a native P-256 key.
    enum Storage: CaseIterable, Identifiable {
        case synced, thisDevice, touchID, secureEnclave
        var id: Self { self }
        var title: String {
            switch self {
            case .synced: return "Synced across your devices (iCloud)"
            case .thisDevice: return "This device only"
            case .touchID: return "This device · Touch ID"
            case .secureEnclave: return "Secure Enclave · this Mac, not exportable (P-256)"
            }
        }
        /// Whether this row asks for authentication (and shows a "Require" picker).
        var isAuthenticated: Bool { self == .touchID || self == .secureEnclave }
    }

    @AppStorage(PreferenceKeys.defaultEnclaveAccessControl)
    private var defaultEnclaveAccessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode

    @State private var isPostQuantum = false
    @State private var storage: Storage = .touchID
    @State private var label = ""
    @State private var keychainAuth: KeychainAuth = .biometryOrPasscode
    @State private var accessControl: SecureEnclaveAccessControl = .anyBiometryOrPasscode
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    /// Storage rows offered for the current algorithm. A native Secure Enclave key
    /// is P-256, so it can't (yet) be post-quantum — hide that row for PQ.
    private var availableStorage: [Storage] {
        isPostQuantum ? Storage.allCases.filter { $0 != .secureEnclave } : Storage.allCases
    }

    /// The keychain protection for the non-enclave rows.
    private var keychainProtection: KeychainProtection {
        switch storage {
        case .synced: return .synced
        case .thisDevice: return .local
        case .touchID: return .authenticated(keychainAuth)
        case .secureEnclave: return .local // unused: enclave keys take a different path
        }
    }

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
                    .onChange(of: isPostQuantum) { _, pq in
                        // A native enclave key is P-256; it can't be post-quantum.
                        if pq, storage == .secureEnclave { storage = .thisDevice }
                    }
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
                warning("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable. Export a backup if you'd want it back.")
            }
            if storage == .secureEnclave, !model.secureEnclaveAvailable {
                warning("This Mac doesn’t have a Secure Enclave.")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(storage == .secureEnclave && !model.secureEnclaveAvailable)
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

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Names the exact key kind (curve/algorithm in parentheses) and what the
    /// chosen storage means — so nothing about the resulting key is hidden.
    private var explanation: LocalizedStringKey {
        switch storage {
        case .secureEnclave:
            return "A **Secure Enclave** key (P-256): sealed by this Mac’s enclave, so you still hold it and can export it for backup, but it only works on the Mac that generated it. Compatible with age-plugin-se."
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
                try model.generateSecureEnclave(label: label, accessControl: accessControl)
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
