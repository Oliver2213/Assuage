import AppKit

/// Registers the system Services provider once the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = serviceProvider
        // Nudge the system to (re)scan our advertised services during development.
        NSUpdateDynamicServices()
    }
}
