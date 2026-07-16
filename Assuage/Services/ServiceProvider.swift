import AppKit
import AssuageCore

/// What a system Service asked us to do.
enum ServiceAction: Sendable {
    case encrypt, decrypt, check
    /// Open the Import Keys sheet loaded with an identity file (`.age-identity` /
    /// `.age-identities`), routed from `AppDelegate`, not a Services message.
    case importIdentities
}

/// A request arriving from the system Services / Finder menu.
struct ServiceRequest: Equatable, Sendable, Identifiable {
    let id = UUID()
    let action: ServiceAction
    let text: String?
    let files: [URL]
}

/// A request to show the "Verify Signed Note" result panel for some pasted text.
/// Distinct from `ServiceRequest` because verification opens its own panel rather
/// than routing into a main window's compose state.
struct VerifyServiceRequest: Equatable, Sendable, Identifiable {
    let id = UUID()
    let text: String
}

/// Carries incoming Service requests from the (AppKit) provider to SwiftUI.
@MainActor
@Observable
final class ServiceBus {
    static let shared = ServiceBus()
    /// Encrypt / decrypt / check / import — routed into the frontmost window.
    var request: ServiceRequest?
    /// A signed note to verify — opens the result panel (see `VerifyResultView`).
    var verifyRequest: VerifyServiceRequest?
    private init() {}
}

/// Receives text / files from the system Services menu and Finder. Registered as
/// `NSApplication.shared.servicesProvider`; method names match `NSMessage` in
/// Info.plist. A crypto tool shouldn't silently transform other apps' data, so
/// each service brings the app forward with the content loaded, rather than
/// returning to the pasteboard.
final class ServiceProvider: NSObject {
    @objc func encryptService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        deliver(.encrypt, from: pasteboard)
    }

    @objc func decryptService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        deliver(.decrypt, from: pasteboard)
    }

    @objc func checkService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        deliver(.check, from: pasteboard)
    }

    /// Sign the selected text as a signed note and hand it back on the pasteboard,
    /// which replaces the selection in place. Unlike the other services this does
    /// its work here — signing needs no recipient choices, so it never brings the
    /// app forward (a protected key may still prompt for Touch ID). On failure the
    /// selection is left untouched and a short alert explains why.
    @objc func signNoteService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = NSLocalizedString("Select some text to sign.", comment: "") as NSString
            return
        }
        do {
            let signed = try NoteSigningService.sign(text)
            pasteboard.clearContents()
            pasteboard.setString(signed, forType: .string)
        } catch let failure {
            error.pointee = signFailureMessage(for: failure) as NSString
            Task { @MainActor in Self.presentSignFailure(failure) }
        }
    }

    /// Verify the selected signed note. Hands off to the result panel rather than
    /// transforming anything — the selection is read-only here.
    @objc func verifyNoteService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = NSLocalizedString("Select a signed note to verify.", comment: "") as NSString
            return
        }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            ServiceBus.shared.verifyRequest = VerifyServiceRequest(text: text)
            VerifyPanel.shared.show(library: .shared, people: .shared)
        }
    }

    /// The error string returned to the calling app (shown briefly in its UI).
    private func signFailureMessage(for error: Error) -> String {
        if case AssuageError.noIdentities = error {
            return NSLocalizedString("No note signing key to sign with.", comment: "")
        }
        return error.localizedDescription
    }

    /// A fuller explanation, as an alert, since the calling app's inline error is
    /// terse and easy to miss.
    @MainActor private static func presentSignFailure(_ error: Error) {
        let alert = NSAlert()
        if case AssuageError.noIdentities = error {
            alert.messageText = NSLocalizedString("No signing key", comment: "")
            alert.informativeText = NSLocalizedString(
                "Generate a note signing key in \(AppInfo.name) first, then try signing again.",
                comment: "")
        } else {
            alert.messageText = NSLocalizedString("Couldn’t sign the note", comment: "")
            alert.informativeText = error.localizedDescription
        }
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func deliver(_ action: ServiceAction, from pasteboard: NSPasteboard) {
        let text = pasteboard.string(forType: .string)
        let files = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        let request = ServiceRequest(action: action, text: text, files: files)

        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            ServiceBus.shared.request = request
        }
    }
}
