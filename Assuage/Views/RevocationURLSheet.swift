import SwiftUI
import AssuageCore

/// Collect the URL of a contact's revoked-key list for one key kind. Checking that
/// list later removes any matching key you hold. Hands the URL back via `onAdd`.
struct RevocationURLSheet: View {
    let kind: ContactRevocationField
    let contactName: String
    let onAdd: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var error: String?

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var who: String {
        contactName.isEmpty ? String(localized: "this contact") : contactName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revoked \(kind.keyTypeName) keys list").font(.headline)
            Text("A URL where \(who) publishes the \(kind.keyTypeName) keys they’ve retired — one per line. Checking it removes any matching key you hold, including keys you added by hand.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://…", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private func add() {
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            error = String(localized: "Enter a valid http(s) URL.")
            return
        }
        onAdd(url)
        dismiss()
    }
}
