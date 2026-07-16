import SwiftUI

@main
struct AssuageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The one key library, shared by every window and by the note Services.
    @State private var library = KeyLibrary.shared
    /// The one people/contacts library, shared by every window and the verify panel.
    @State private var people = PeopleLibrary.shared

    var body: some Scene {
        WindowGroup {
            WindowRoot(library: library, people: people)
        }
        .commands {
            AssuageCommands()
        }

        Settings {
            SettingsView()
                .environment(people)
        }
    }
}

/// The root of each window. Builds a per-window `AppModel` over the shared key
/// `library`, so compose state (input, queues, selection) is independent per
/// window while the keys stay the same everywhere. The model is also published
/// as a focused scene value so the menu commands target the active window.
private struct WindowRoot: View {
    @State private var model: AppModel
    private let people: PeopleLibrary

    init(library: KeyLibrary, people: PeopleLibrary) {
        _model = State(initialValue: AppModel(library: library))
        self.people = people
    }

    var body: some View {
        ContentView()
            .environment(model)
            .environment(people)
            .focusedSceneValue(\.appModel, model)
            .frame(minWidth: 760, minHeight: 520)
    }
}
