import Foundation

/// One place the app plugs into macOS, listed in the System Integrations settings
/// tab. Informational only — the user enables or disables these in System Settings;
/// the app can't toggle them and reaches no network.
struct SystemIntegration: Identifiable {
    let name: String
    let detail: String
    let systemImage: String
    var id: String { name }

    /// The integrations the app ships, in display order.
    static let all: [SystemIntegration] = [
        SystemIntegration(
            name: "Services menu",
            detail: "Encrypt, decrypt, or check the current selection from the Services menu in any app. You can also sign selected text as a signed note — it replaces the selection — or verify a signed note.",
            systemImage: "filemenu.and.selection"
        ),
        SystemIntegration(
            name: "Finder",
            detail: "Encrypt or decrypt files and folders from Finder’s Quick Actions menu.",
            systemImage: "folder"
        ),
        SystemIntegration(
            name: "Quick Look",
            detail: "Press Space on a .age file to see its recipients, armor, and size — without decrypting it.",
            systemImage: "eye"
        ),
    ]
}
