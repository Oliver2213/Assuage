import Foundation
import AppKit
import os

private let log = Logger(subsystem: "dev.smoll.Assuage.quickaction", category: "forward")

/// Finder Quick Action entry point. Collects the selected items and hands them to
/// the main Assuage app via LaunchServices — which grants the app sandbox access
/// to exactly those items — then finishes. No crypto happens in the extension:
/// the app inspects the selection and drives encrypt or decrypt.
///
/// The Encrypt and Decrypt actions share this exact handler; they differ only in
/// display name and activation rule (Encrypt shows for any item, Decrypt only for
/// `.age` files). The verb the user picked isn't forwarded — the app decides from
/// the file contents (all age → decrypt, otherwise → encrypt).
///
/// Named `QuickActionForwarder` (not `ActionRequestHandler`) so it never collides
/// with the file Xcode's Action Extension template generates. `Info.plist` points
/// `NSExtensionPrincipalClass` here.
final class QuickActionForwarder: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task {
            let items = (context.inputItems as? [NSExtensionItem]) ?? []
            let urls = await Self.resolveURLs(items)
            if urls.isEmpty {
                log.error("resolved no file URLs from \(items.count) item(s) — not opening app")
            } else {
                await Self.open(urls)
            }
            // Return the selection unchanged — we don't modify the files, so Finder
            // must not treat them as consumed (returning nothing deletes/moves them).
            context.completeRequest(returningItems: context.inputItems, completionHandler: nil)
        }
    }

    /// Every selected item resolved to its on-disk file URL, in selection order.
    private static func resolveURLs(_ items: [NSExtensionItem]) async -> [URL] {
        var urls: [URL] = []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if let url = await resolveURL(provider) { urls.append(url) }
        }
        return urls
    }

    /// Get a provider's original file URL. Finder vends a selected file under its
    /// own content type (e.g. `public.plain-text`, `public.folder`), not
    /// `public.file-url`, so we ask each registered type for its in-place file
    /// representation and take the first that resolves. We keep only the path — the
    /// security-scoped URL is valid only inside the callback, but the path
    /// identifies the original file and LaunchServices re-grants the app access
    /// when we open it.
    private static func resolveURL(_ provider: NSItemProvider) async -> URL? {
        for type in provider.registeredTypeIdentifiers {
            if let url = await loadInPlaceURL(provider, type) { return url }
        }
        return nil
    }

    private static func loadInPlaceURL(_ provider: NSItemProvider, _ type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, _, error in
                if let error { log.error("loadInPlace(\(type, privacy: .public)): \(error.localizedDescription, privacy: .public)") }
                // Rebuild a plain file URL from the path so it outlives the callback.
                continuation.resume(returning: url.map { URL(fileURLWithPath: $0.path) })
            }
        }
    }

    /// Open (or activate) the containing app with the selected items. LaunchServices
    /// grants the app access to exactly these URLs — so it can write output beside
    /// each original without any extra entitlement here.
    @MainActor
    private static func open(_ urls: [URL]) async {
        guard let app = containerAppURL() else {
            log.error("could not resolve the container app URL")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
        } catch {
            log.error("NSWorkspace.open failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// This extension lives at `…/Assuage.app/Contents/PlugIns/<name>.appex`;
    /// step up three levels to the containing `.app`.
    private static func containerAppURL() -> URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.pathExtension == "app" ? url : nil
    }
}
