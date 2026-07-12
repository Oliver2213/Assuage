import SwiftUI
import AssuageCore

/// Chooses recipients: a checkbox grid over the user's own keys plus ad-hoc
/// public keys pasted in as `age1…` strings.
struct RecipientSelector: View {
    let identities: [AgeIdentity]
    @Binding var selectedIdentityIDs: Set<UUID>
    @Binding var extraRecipients: [AgeRecipient]

    @State private var field = ""
    @State private var parseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if identities.isEmpty && extraRecipients.isEmpty {
                Text("No recipients yet — add a public key below, or generate one in the Keys tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !identities.isEmpty {
                IdentityCheckTable(identities: identities, selection: $selectedIdentityIDs)
            }

            ForEach(extraRecipients) { recipient in
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    PublicKeyText(recipient: recipient)
                    Spacer()
                    Button("Remove recipient", systemImage: "xmark.circle.fill") {
                        extraRecipients.removeAll { $0 == recipient }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Add a recipient (age1…)", text: $field)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(field.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func add() {
        let raw = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        do {
            let recipient = try AgeRecipient(parsing: raw)
            if !extraRecipients.contains(recipient) {
                extraRecipients.append(recipient)
            }
            field = ""
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }
}
