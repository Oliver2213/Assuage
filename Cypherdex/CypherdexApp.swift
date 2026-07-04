import SwiftUI

@main
struct CypherdexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CypherdexCommands(model: model)
        }
    }
}
