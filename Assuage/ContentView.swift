import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var controlActiveState
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
            .navigationTitle(AppInfo.name)
        } detail: {
            switch model.selection ?? .encrypt {
            case .encrypt: EncryptView()
            case .decrypt: DecryptView()
            case .keys: KeysView()
            }
        }
        .sheet(isPresented: $model.showGenerateSheet) { GenerateKeySheet() }
        .sheet(isPresented: $model.showImportSheet) { ImportKeysSheet() }
        .sheet(item: $model.editingKey) { EditKeySheet(identity: $0) }
        .sheet(item: $model.exportingKeys) { ExportKeySheet(identities: $0.identities) }
        .onChange(of: bus.request) { _, request in
            deliver(request)
        }
        .onChange(of: controlActiveState) { _, state in
            if state == .key { deliver(bus.request) }
        }
        .onAppear { deliver(bus.request) }
    }

    /// Route a queued Service/Finder request into *this* window's model, but only
    /// when this is the key (frontmost) window — so an open lands in one window and
    /// leaves any work in the others untouched. Clears the shared request once taken.
    private func deliver(_ request: ServiceRequest?) {
        guard controlActiveState == .key, let request else { return }
        model.handle(request)
        bus.request = nil
    }
}

#Preview {
    ContentView()
        .environment(AppModel(library: KeyLibrary()))
}
