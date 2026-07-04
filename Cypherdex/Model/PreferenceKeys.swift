/// Central home for `@AppStorage` keys so the Settings pane and the views that
/// read a preference can't drift apart on a typo'd string.
enum PreferenceKeys {
    static let defaultEnclaveAccessControl = "defaultEnclaveAccessControl"
    static let exportAuthPolicy = "exportAuthPolicy"
    static let requireAuthToDelete = "requireAuthToDelete"

    // Clipboard protections (see `Pasteboard`). Conceal defaults on; clear-after
    // defaults off with a 30s delay; protect-all defaults off (sensitive only).
    static let clipboardConcealMarker = "clipboardConcealMarker"
    static let clipboardClearAfterCopy = "clipboardClearAfterCopy"
    static let clipboardClearDelay = "clipboardClearDelay"
    static let clipboardProtectAllCopies = "clipboardProtectAllCopies"
}
