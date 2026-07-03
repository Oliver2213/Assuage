import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(AppModel.Panel.allCases) { panel in
                    Label(panel.title, systemImage: panel.systemImage)
                        .tag(panel)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .navigationTitle("Cypherdex")
        } detail: {
            switch model.selection ?? .encrypt {
            case .encrypt: EncryptView()
            case .decrypt: DecryptView()
            case .keys: KeysView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .environment(CryptoEngine())
}
