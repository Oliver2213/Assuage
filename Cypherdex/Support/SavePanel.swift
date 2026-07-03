import AppKit
import UniformTypeIdentifiers

/// Thin wrappers around `NSSavePanel` for exporting text and binary. Fine to use
/// directly while the app is non-sandboxed; revisit for the sandboxed variant.
@MainActor
enum SavePanel {
    static func save(_ data: Data, suggestedName: String, contentType: UTType? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if let contentType { panel.allowedContentTypes = [contentType] }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    static func save(text: String, suggestedName: String) {
        save(Data(text.utf8), suggestedName: suggestedName, contentType: .plainText)
    }
}
