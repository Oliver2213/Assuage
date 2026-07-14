import SwiftUI

/// The "current fingerprints" caution, shown when a key is bound to the current
/// biometric set (`biometryCurrentSet`). Shared by the generate/edit key sheets so
/// the copy is written once.
struct CurrentBiometryWarning: View {
    /// Generate sheets add a "keep a backup" hint; edit sheets omit it (by then you
    /// already hold the key).
    var includeBackupHint = false

    var body: some View {
        if includeBackupHint {
            WarningLabel("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable. Export a backup if you'd want it back.")
        } else {
            WarningLabel("“Current fingerprints” ties this key to your fingerprints as they are now — adding or removing any fingerprint permanently makes it unreadable.")
        }
    }
}
