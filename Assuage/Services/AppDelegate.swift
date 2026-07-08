import AppKit

/// Registers the system Services provider once the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = serviceProvider
        // Nudge the system to (re)scan our advertised services during development.
        NSUpdateDynamicServices()
    }

    /// Files opened from Finder ("Open With", double-click) or dropped on the app
    /// icon. We declare the `.age` type (see Info.plist), so these are encrypted
    /// files — route them into the Decrypt panel's queue via the same bus the
    /// Services provider uses.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        let request = ServiceRequest(action: .decrypt, text: nil, files: files)
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            ServiceBus.shared.request = request
        }
    }
}
