import SwiftUI
import UniformTypeIdentifiers
import CypherdexCore

/// Import age identity files with per-key control. First you set defaults (name,
/// sync, whether to delete the file afterward) and choose a file; then each key
/// the file contains becomes an editable row you can rename, toggle sync on, or
/// deselect before finalizing.
struct ImportKeysSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // Defaults, chosen before picking a file.
    @State private var defaultName = ""
    @State private var defaultStorage: KeychainStorageMode = .authenticated
    @State private var defaultAuth: KeychainAuth = .biometryOrPasscode
    @State private var deleteFileAfter = false

    // Populated once a file is parsed.
    @State private var fileURL: URL?
    @State private var drafts: [ImportKeyDraft] = []

    @State private var showImporter = false
    @State private var showLossConfirmation = false
    @State private var errorMessage = ""
    @State private var isErrorPresented = false
    /// How many duplicate keys within the chosen file were collapsed on load.
    @State private var duplicatesRemoved = 0

    private var hasFile: Bool { fileURL != nil }
    private var selectedCount: Int { drafts.filter(\.include).count }
    private var droppedCount: Int { drafts.count - selectedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Keys")
                .font(.title2.bold())

            Form {
                TextField("Default name", text: $defaultName, prompt: Text("Optional — overrides names below"))
                Picker("Storage", selection: $defaultStorage) {
                    ForEach(KeychainStorageMode.allCases) { Text($0.title).tag($0) }
                }
                if defaultStorage == .authenticated {
                    Picker("Require", selection: $defaultAuth) {
                        ForEach(KeychainAuth.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Toggle("Delete the file after importing", isOn: $deleteFileAfter)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: defaultName) { applyDefaultNames() }
            .onChange(of: defaultStorage) { applyDefaultStorage() }

            if defaultStorage == .authenticated, defaultAuth == .currentBiometry {
                Label("“Current fingerprints” ties these keys to your fingerprints as they are now — adding or removing any fingerprint permanently makes them unreadable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasFile {
                ImportReviewList(drafts: $drafts, duplicatesRemoved: duplicatesRemoved)
            } else {
                Text("Choose an age identity file (one or more `AGE-SECRET-KEY-1…` keys). You’ll review and name each key before it’s imported. Imported keys are stored in your keychain — the Secure Enclave can only hold keys it generated itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if hasFile {
                    Button("Clear", role: .destructive, action: reset)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                if hasFile {
                    Button("Import", action: startImport)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("i", modifiers: .command)
                        .disabled(selectedCount == 0)
                } else {
                    Button("Choose File…") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            load(url)
        }
        .confirmationDialog(
            "Delete the file with unselected keys?",
            isPresented: $showLossConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import & Delete File", role: .destructive, action: finishImport)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("^[\(droppedCount) key](inflect: true) not selected for import will be lost when the file is deleted.")
        }
        .alert("Couldn’t import keys", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Loading & editing

    private func load(_ url: URL) {
        do {
            let keys = try model.importableKeys(at: url)
            // Collapse keys that repeat within the file (same recipient), keeping
            // the first occurrence and counting the rest for the summary line.
            var seen = Set<AgeRecipient>()
            let unique = keys.filter { seen.insert($0.recipient).inserted }
            let existing = Set(model.identities.map(\.recipient))
            fileURL = url
            duplicatesRemoved = keys.count - unique.count
            drafts = unique.map { key in
                let alreadyExists = existing.contains(key.recipient)
                // Keys we already hold default to skipped, but stay togglable in case
                // the user deliberately wants a second, separately-labeled copy.
                return ImportKeyDraft(key: key, include: !alreadyExists, name: "", storage: defaultStorage, alreadyExists: alreadyExists)
            }
            applyDefaultNames()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }

    /// Name every key. With no default, that's the file's base name (all the same,
    /// per the "filename for all" rule); with a default, it overrides — numbered
    /// when the file holds more than one key.
    private func applyDefaultNames() {
        guard !drafts.isEmpty else { return }
        let base = defaultName.trimmingCharacters(in: .whitespaces).isEmpty
            ? (fileURL?.deletingPathExtension().lastPathComponent ?? "Imported key")
            : defaultName.trimmingCharacters(in: .whitespaces)
        for index in drafts.indices {
            drafts[index].name = drafts.count > 1 ? "\(base) \(index + 1)" : base
        }
    }

    private func applyDefaultStorage() {
        for index in drafts.indices { drafts[index].storage = defaultStorage }
    }

    /// Back to a clean slate: forget the file, the parsed keys, and every option.
    private func reset() {
        fileURL = nil
        drafts = []
        defaultName = ""
        defaultStorage = .authenticated
        defaultAuth = .biometryOrPasscode
        deleteFileAfter = false
        duplicatesRemoved = 0
    }

    // MARK: Importing

    private func startImport() {
        if deleteFileAfter && droppedCount > 0 {
            showLossConfirmation = true
        } else {
            finishImport()
        }
    }

    private func finishImport() {
        do {
            let identities = try drafts
                .filter(\.include)
                .map { try AgeIdentity(importingX25519: $0.key.secretKey, label: $0.name, protection: $0.storage.protection(auth: defaultAuth)) }
            try model.importIdentities(identities)
            if deleteFileAfter, let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
