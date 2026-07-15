import Foundation

extension URL {
    /// Read this file as UTF-8 text, wrapped in a security-scoped access claim — the
    /// dance a sandboxed app must do around a user-chosen file (from `.fileImporter`)
    /// before it may read it.
    func readingSecurityScopedText() throws -> String {
        let scoped = startAccessingSecurityScopedResource()
        defer { if scoped { stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: self, encoding: .utf8)
    }
}
