import SwiftUI

/// Menu-bar commands: panel navigation (⌘1–⌘3), the Encrypt/Decrypt sub-tabs
/// (⌘⇧1 / ⌘⇧2) and their run action (⌘↩ in the Actions menu), plus key management
/// (⌘K generate, ⌘I import in the File menu). All drive `AppModel` state directly.
///
/// The run action is a menu command, not a button shortcut, because a focused
/// multiline field would otherwise swallow ⌘↩ before a toolbar button saw it.
///
/// ⌘I *opens* the import sheet; committing the import is ⇧⌘I, scoped to the sheet
/// itself (see `ImportKeysSheet`) so it can't fire from elsewhere.
struct AssuageCommands: Commands {
    /// The active window's model (each window has its own), so commands act on
    /// whichever window is frontmost. `nil` when no window is focused.
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Generate age Keypair…") { model?.showGenerateSheet = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)
            Button("Generate Signing Key…") { model?.showGenerateSigningKeySheet = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Import Identity…") { model?.showImportSheet = true }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(model == nil)
            Divider()
            Button("Edit Key…") { model?.editingKey = model?.singleSelectedKey }
                .disabled(model?.singleSelectedKey == nil)
            Button("Export All Identities…") {
                if let model { model.exportingKeys = ExportRequest(identities: model.identities) }
            }
            .disabled(model?.identities.isEmpty ?? true)
            Button("Copy All Recipients") {
                if let model { model.copyRecipients(for: model.identities) }
            }
            .disabled(model?.identities.isEmpty ?? true)
            Button("Export All Recipients…") {
                if let model { model.exportRecipients(for: model.identities) }
            }
            .disabled(model?.identities.isEmpty ?? true)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(AppModel.Panel.allCases.enumerated()), id: \.element) { index, panel in
                Button(panel.title) { model?.selection = panel }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(model == nil)
            }
            Divider()
            if let model {
                // ⌘⇧1 / ⌘⇧2 switch the current panel's sub-tab: Encrypt/Decrypt on
                // Files and Text, Encryption/Signing on Keys. Toggles (not Buttons)
                // so the active sub-tab shows a checkmark.
                if model.selection == .keys {
                    Toggle("Encryption Keys", isOn: Binding(
                        get: { model.keyCategory == .encryption },
                        set: { if $0 { model.keyCategory = .encryption } }
                    ))
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                    Toggle("Signing Keys", isOn: Binding(
                        get: { model.keyCategory == .signing },
                        set: { if $0 { model.keyCategory = .signing } }
                    ))
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                } else {
                    Toggle("Encrypt Mode", isOn: Binding(
                        get: { model.operation == .encrypt },
                        set: { if $0 { model.operation = .encrypt } }
                    ))
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                    Toggle("Decrypt Mode", isOn: Binding(
                        get: { model.operation == .decrypt },
                        set: { if $0 { model.operation = .decrypt } }
                    ))
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                }
            }
        }

        // The visible compose panel's primary action. ⌘↩ resolves to whichever of
        // Encrypt / Decrypt matches the current sub-tab; only that one is enabled.
        CommandMenu("Actions") {
            Button("Encrypt") { model?.runComposeAction = true }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun(.encrypt))
            Button("Decrypt") { model?.runComposeAction = true }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun(.decrypt))
        }

        CommandGroup(replacing: .help) {
            Link("age Encryption Website", destination: URL(string: "https://age-encryption.org")!)
            Link("Community Cryptography Standards Project", destination: URL(string: "https://c2sp.org")!)
        }
    }

    /// Whether ⌘↩ should run `operation`: only on a compose panel whose sub-tab
    /// currently shows it.
    private func canRun(_ operation: AppModel.Operation) -> Bool {
        guard let model else { return false }
        return model.selection.hasOperations && model.operation == operation
    }
}
