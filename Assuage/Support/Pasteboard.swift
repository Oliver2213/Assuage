import AppKit
import Foundation

/// Central place to copy text to the clipboard, honoring the user's clipboard
/// preferences (see `SettingsView`).
///
/// - **Conceal marker** (`org.nspasteboard.ConcealedType`): best-effort signal —
///   well-behaved clipboard managers treat the copy as confidential and don't log
///   it. It is *not* a documented way to block Handoff / Universal Clipboard;
///   AppKit has no such flag for the general pasteboard.
/// - **Auto-clear**: the reliable protection. We wipe the clipboard after a delay,
///   but only if nothing else has been copied since (tracked via `changeCount`).
///
/// `sensitive` content (e.g. decrypted plaintext) is always eligible; public
/// content (recipients, ciphertext) is protected only when the user turns on
/// "protect all copies".
enum Pasteboard {
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func copy(_ text: String, sensitive: Bool) {
        let defaults = UserDefaults.standard
        let protect = sensitive || defaults.bool(forKey: PreferenceKeys.clipboardProtectAllCopies)
        // Conceal defaults on; the others default off / 30s.
        let conceal = protect && (defaults.object(forKey: PreferenceKeys.clipboardConcealMarker) as? Bool ?? true)
        let autoClear = protect && defaults.bool(forKey: PreferenceKeys.clipboardClearAfterCopy)

        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if conceal {
            item.setData(Data(), forType: concealedType)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        if autoClear {
            let seconds = defaults.object(forKey: PreferenceKeys.clipboardClearDelay) as? Int ?? 30
            scheduleClear(after: max(1, seconds), changeCount: pasteboard.changeCount)
        }
    }

    /// Clear the clipboard after `seconds`, unless something else was copied in the
    /// meantime (a changed `changeCount` means we no longer own the contents).
    private static func scheduleClear(after seconds: Int, changeCount: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
        }
    }
}
