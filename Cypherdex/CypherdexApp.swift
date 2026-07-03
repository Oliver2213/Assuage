import SwiftUI

@main
struct CypherdexApp: App {
    @State private var model = AppModel()
    @State private var engine = CryptoEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(engine)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Generate age Keypair…") {
                    model.selection = .keys
                    NotificationCenter.default.post(name: .generateKeypairRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Link("age Encryption Website", destination: URL(string: "https://age-encryption.org")!)
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the menu command to ask the Keys panel to open its generate sheet.
    static let generateKeypairRequested = Notification.Name("generateKeypairRequested")
}
