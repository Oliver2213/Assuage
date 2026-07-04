import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var bus = ServiceBus.shared

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
        .sheet(isPresented: $model.showGenerateSheet) { GenerateKeySheet() }
        .sheet(isPresented: $model.showImportSheet) { ImportKeysSheet() }
        .onChange(of: bus.request) { _, request in
            deliver(request)
        }
        .onAppear { deliver(bus.request) }
    }

    /// Route a queued Service request into the model, then clear it.
    private func deliver(_ request: ServiceRequest?) {
        guard let request else { return }
        model.handle(request)
        bus.request = nil
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
