import SwiftUI

/// The app's Preferences window (⌘,), split into tabs. macOS supplies the ⌘,
/// menu item and shortcut automatically from the `Settings` scene.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Clipboard", systemImage: "doc.on.clipboard") {
                ClipboardSettingsView()
            }
            Tab("System Integrations", systemImage: "puzzlepiece.extension") {
                SystemIntegrationsView()
            }
        }
        .frame(width: 500)
        .frame(minHeight: 400)
    }
}

#Preview {
    SettingsView()
}
