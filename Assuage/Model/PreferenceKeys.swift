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

    /// Whether the export sheet may copy a private key to the clipboard. Off by
    /// default; when on, a "Copy to Clipboard" action appears in the export sheet.
    static let allowClipboardExport = "allowClipboardExport"

    /// Whether a copied/exported recipients file precedes each public key with a
    /// `# name` comment. Off by default — a bare recipients list, one per line.
    static let recipientCommentLabels = "recipientCommentLabels"

    /// Whether newly generated keys default to post-quantum (X-Wing / ML-KEM).
    /// Off by default; only meaningful on macOS 26+, where post-quantum exists, so
    /// the Settings toggle is shown only there.
    static let defaultToPostQuantum = "defaultToPostQuantum"

    /// Whether encrypting prompts for Touch ID first. Off by default. This confirms
    /// intent on an unlocked Mac — encryption uses only public key material, so it's
    /// a convenience gate, not a security boundary (a pref can't be one).
    static let confirmTouchIDBeforeEncrypt = "confirmTouchIDBeforeEncrypt"

    /// How public keys are shown in the UI (abbreviated vs full). Display only —
    /// copy and export always use the full key.
    static let publicKeyDisplay = "publicKeyDisplay"
}
