import SwiftUI

/// Menu-bar commands: panel navigation (⌘1–⌘3 in the View menu) plus the
/// key-management actions (⌘K generate, ⌘I import in the File menu). All drive
/// `AppModel` state directly, so they work no matter which panel is showing.
///
/// ⌘I *opens* the import sheet; committing the import is ⇧⌘I, scoped to the sheet
/// itself (see `ImportKeysSheet`) so it can't fire from elsewhere.
struct CypherdexCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Generate age Keypair…") { model.showGenerateSheet = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("Import Identity…") { model.showImportSheet = true }
                .keyboardShortcut("i", modifiers: .command)
            Divider()
            Button("Edit Key…") { model.editingKey = model.singleSelectedKey }
                .disabled(model.singleSelectedKey == nil)
            Button("Export All Identities…") { model.exportingKeys = ExportRequest(identities: model.identities) }
                .disabled(model.identities.isEmpty)
            Button("Copy All Recipients") { model.copyRecipients(for: model.identities) }
                .disabled(model.identities.isEmpty)
            Button("Export All Recipients…") { model.exportRecipients(for: model.identities) }
                .disabled(model.identities.isEmpty)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(AppModel.Panel.allCases.enumerated()), id: \.element) { index, panel in
                Button(panel.title) { model.selection = panel }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }

        CommandGroup(replacing: .help) {
            Link("age Encryption Website", destination: URL(string: "https://age-encryption.org")!)
        }
    }
}
