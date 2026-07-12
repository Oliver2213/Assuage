import AppKit
import AssuageCore

/// Registers the system Services provider once the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = serviceProvider
        // Nudge the system to (re)scan our advertised services during development.
        NSUpdateDynamicServices()
    }

    /// Files opened from Finder ("Open With", double-click), dropped on the app
    /// icon, or forwarded by the Encrypt/Decrypt Finder Quick Actions. Route them
    /// by content via the same bus the Services provider uses: if every item is an
    /// age file we decrypt, otherwise we encrypt (a folder or plaintext item means
    /// the user means to encrypt). The sniff is a cheap header peek — see
    /// `AgeFileInspector.isAgeFile`. A folder in an encrypt request is zipped by
    /// the encrypt pipeline. (Re-encrypting an all-age selection isn't reachable
    /// this way — that lands in the Encrypt panel manually instead.)
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        let request: ServiceRequest
        let identityFiles = files.filter(Self.isIdentityFile)
        if !identityFiles.isEmpty {
            // Opening an identity file goes to import, not encrypt/decrypt.
            request = ServiceRequest(action: .importIdentities, text: nil, files: identityFiles)
        } else {
            let action: ServiceAction = files.allSatisfy(AgeFileInspector.isAgeFile) ? .decrypt : .encrypt
            request = ServiceRequest(action: action, text: nil, files: files)
        }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            ServiceBus.shared.request = request
        }
    }

    /// Whether a file is an age identity file, by extension.
    private static func isIdentityFile(_ url: URL) -> Bool {
        ["age-identity", "age-identities"].contains(url.pathExtension.lowercased())
    }
}
