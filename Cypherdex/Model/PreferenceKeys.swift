/// Central home for `@AppStorage` keys so the Settings pane and the views that
/// read a preference can't drift apart on a typo'd string.
enum PreferenceKeys {
    static let defaultEnclaveAccessControl = "defaultEnclaveAccessControl"
    static let exportAuthPolicy = "exportAuthPolicy"
    static let requireAuthToDelete = "requireAuthToDelete"
}
