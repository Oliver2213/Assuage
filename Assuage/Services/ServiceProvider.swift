import AppKit

/// What a system Service asked us to do.
enum ServiceAction: Sendable {
    case encrypt, decrypt, check
}

/// A request arriving from the system Services / Finder menu.
struct ServiceRequest: Equatable, Sendable, Identifiable {
    let id = UUID()
    let action: ServiceAction
    let text: String?
    let files: [URL]
}

/// Carries incoming Service requests from the (AppKit) provider to SwiftUI.
@MainActor
@Observable
final class ServiceBus {
    static let shared = ServiceBus()
    var request: ServiceRequest?
    private init() {}
}

/// Receives text / files from the system Services menu and Finder. Registered as
/// `NSApplication.shared.servicesProvider`; method names match `NSMessage` in
/// Info.plist. A crypto tool shouldn't silently transform other apps' data, so
/// each service brings Cypherdex forward with the content loaded, rather than
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
