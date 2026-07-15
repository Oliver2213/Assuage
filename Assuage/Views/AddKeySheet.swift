import SwiftUI
import AssuageCore

/// A small sheet to paste one public key of a specific kind, validated against that
/// kind. Shared by the "Add Key" menu in the person editor (one sheet, three kinds).
struct AddKeySheet: View {
    enum Kind: Identifiable, CaseIterable {
        case age, ssh, verifier
        var id: Self { self }

        var menuTitle: String {
            switch self {
            case .age: "Age Public Key…"
            case .ssh: "SSH Public Key…"
            case .verifier: "Verifier Key…"
            }
        }
        var title: String {
            switch self {
            case .age: "Add an age public key"
            case .ssh: "Add an SSH public key"
            case .verifier: "Add a note verifier key"
            }
        }
        var prompt: String {
            switch self {
            case .age: "age1…"
            case .ssh: "ssh-ed25519 AAAA…"
            case .verifier: "name+hash+base64"
            }
        }
        var mismatch: String {
            switch self {
            case .age: "That isn’t an age public key."
            case .ssh: "That isn’t an SSH public key."
            case .verifier: "That isn’t a note verifier key."
            }
        }

        /// Whether a parsed key is of this kind.
        func accepts(_ decoded: ContactKeyField.Decoded) -> Bool {
            switch (self, decoded) {
            case (.age, .recipient(let r)): r.kind != .sshEd25519
            case (.ssh, .recipient(let r)): r.kind == .sshEd25519
            case (.verifier, .verifier): true
            default: false
            }
        }
    }

    let kind: Kind
    let onAdd: (ContactKeyField.Decoded) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var error: String?

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title).font(.headline)
            TextField(kind.prompt, text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .lineLimit(2...5)
                .onSubmit(add)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        guard let decoded = ContactKeyField.parse(trimmed) else {
            error = "That isn’t a recognized public key."
            return
        }
        guard kind.accepts(decoded) else {
            error = kind.mismatch
            return
        }
        onAdd(decoded)
        dismiss()
    }
}
