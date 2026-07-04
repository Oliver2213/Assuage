import SwiftUI
import CypherdexCore

/// Edit an existing key. For now that's the label (a rename); storage/protection
/// transitions will join here later — the Storage row previews where they'll go.
struct EditKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let identity: AgeIdentity
    @State private var label: String
    @State private var errorMessage = ""
    @State private var isErrorPresented = false

    init(identity: AgeIdentity) {
        self.identity = identity
        _label = State(initialValue: identity.label)
    }

    private var hasChanges: Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines) != identity.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Key")
                .font(.title2.bold())

            Form {
                TextField("Label", text: $label, prompt: Text(identity.defaultName))
                LabeledContent("Public key") {
                    Text(identity.recipient.encoding)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Storage", value: identity.sourceDescription)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
        }
        .padding(20)
        .frame(width: 420)
        .alert("Couldn’t save changes", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func save() {
        do {
            try model.rename(identity, to: label)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
