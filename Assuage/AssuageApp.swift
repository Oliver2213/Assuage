import SwiftUI

@main
struct AssuageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The one key library, shared by every window.
    @State private var library = KeyLibrary()

    var body: some Scene {
        WindowGroup {
            WindowRoot(library: library)
        }
        .commands {
            AssuageCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// The root of each window. Builds a per-window `AppModel` over the shared key
/// `library`, so compose state (input, queues, selection) is independent per
/// window while the keys stay the same everywhere. The model is also published
/// as a focused scene value so the menu commands target the active window.
private struct WindowRoot: View {
    @State private var model: AppModel

    init(library: KeyLibrary) {
        _model = State(initialValue: AppModel(library: library))
    }

    var body: some View {
        ContentView()
            .environment(model)
            .focusedSceneValue(\.appModel, model)
            .frame(minWidth: 760, minHeight: 520)
    }
}
