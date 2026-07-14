import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var bus = ServiceBus.shared

    var body: some View {
        @Bindable var model = model
        // Sidebar on macOS/iPad, bottom tabs on iPhone — one structure.
        TabView(selection: $model.selection) {
            Tab(AppModel.Panel.files.title, systemImage: AppModel.Panel.files.systemImage, value: AppModel.Panel.files) {
                NavigationStack { FilesView() }
            }
            Tab(AppModel.Panel.text.title, systemImage: AppModel.Panel.text.systemImage, value: AppModel.Panel.text) {
                NavigationStack { TextView() }
            }
            Tab(AppModel.Panel.notes.title, systemImage: AppModel.Panel.notes.systemImage, value: AppModel.Panel.notes) {
                NavigationStack { NotesView() }
            }
            Tab(AppModel.Panel.keys.title, systemImage: AppModel.Panel.keys.systemImage, value: AppModel.Panel.keys) {
                NavigationStack { KeysView() }
            }
            Tab(AppModel.Panel.people.title, systemImage: AppModel.Panel.people.systemImage, value: AppModel.Panel.people) {
                NavigationStack { PeopleView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(isPresented: $model.showGenerateSheet) { GenerateKeySheet() }
        .sheet(isPresented: $model.showGenerateSigningKeySheet) { GenerateSigningKeySheet() }
        .sheet(isPresented: $model.showImportSheet) { ImportKeysSheet() }
        .sheet(item: $model.editingKey) { EditKeySheet(identity: $0) }
        .sheet(item: $model.editingSigner) { EditSigningKeySheet(signer: $0) }
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
