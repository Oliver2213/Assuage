import AppKit
import SwiftUI

/// Hosts the "Verify Signed Note" result panel as a standalone AppKit window, so the
/// Service can show it whether or not any main window is open (and without opening
/// one). A single reusable window: re-verifying updates the same panel via the shared
/// `ServiceBus`, which `VerifyResultView` reads.
@MainActor
final class VerifyPanel {
    static let shared = VerifyPanel()
    private var window: NSWindow?
    private init() {}

    /// Show (creating on first use) the verify panel, reading the note off the bus.
    func show(library: KeyLibrary, people: PeopleLibrary) {
        if window == nil {
            let controller = NSHostingController(
                rootView: VerifyResultView(onDone: { [weak self] in self?.window?.close() })
                    .environment(library)
                    .environment(people)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "Verify Signed Note")
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 420))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
