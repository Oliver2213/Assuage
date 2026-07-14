import SwiftUI
import AssuageCore

/// The keychain Storage + "Require" picker pair, shared by the key sheets that offer
/// only keychain storage (Generate Signing Key, Edit Key, Edit Signing Key). The
/// "Require" picker appears only for the Touch ID row.
///
/// `GenerateKeySheet` keeps its own storage picker — it adds the Secure Enclave row
/// and a separate access-control picker, which don't apply here.
struct StoragePicker: View {
    @Binding var storage: KeyStorage
    @Binding var auth: KeychainAuth

    var body: some View {
        Picker("Storage", selection: $storage) {
            ForEach(KeyStorage.keychainCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        if storage == .touchID {
            Picker("Require", selection: $auth) {
                ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }
}
