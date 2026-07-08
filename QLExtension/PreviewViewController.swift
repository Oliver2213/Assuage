import SwiftUI
import CypherdexCore

#if os(macOS)
import Quartz
#else
import QuickLook
#endif

/// Quick Look preview for `.age` files. Inspects the header only — no keys, no
/// decryption — and hosts the shared SwiftUI `AgeFilePreview` (recipients, armor,
/// post-quantum status, size breakdown).
///
/// Cross-platform: AppKit host on macOS, UIKit host on iOS/iPadOS. The SwiftUI
/// body is identical. Principal class in Info.plist:
/// `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PreviewViewController`.
/// Sandboxed; only reads the file it's handed.
#if os(macOS)

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() { view = NSView() }

    func preparePreviewOfFile(at url: URL) async throws {
        let info = try await Task.detached { try AgeFileInspector.inspect(contentsOf: url) }.value
        let hosting = NSHostingController(
            rootView: AgeFilePreview(info: info, filename: url.lastPathComponent)
        )
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        view.addSubview(hosting.view)
    }
}

#else

final class PreviewViewController: UIViewController, QLPreviewingController {
    func preparePreviewOfFile(at url: URL) async throws {
        let info = try await Task.detached { try AgeFileInspector.inspect(contentsOf: url) }.value
        let hosting = UIHostingController(
            rootView: AgeFilePreview(info: info, filename: url.lastPathComponent)
        )
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}

#endif
