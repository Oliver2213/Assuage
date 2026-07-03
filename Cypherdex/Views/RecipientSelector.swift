import SwiftUI
import CypherdexCore

/// Chooses recipients: toggles over the user's own keys plus ad-hoc public keys
/// pasted in as `age1…` strings.
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

            ForEach(identities) { identity in
                Toggle(isOn: isSelected(identity)) {
                    IdentityLabel(identity: identity)
                }
                .toggleStyle(.checkbox)
            }

            ForEach(extraRecipients) { recipient in
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(recipient.encoding)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    private func isSelected(_ identity: AgeIdentity) -> Binding<Bool> {
        Binding(
            get: { selectedIdentityIDs.contains(identity.id) },
            set: { isOn in
                if isOn { selectedIdentityIDs.insert(identity.id) }
                else { selectedIdentityIDs.remove(identity.id) }
            }
        )
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

/// A compact two-line identity label: name over its recipient string.
struct IdentityLabel: View {
    let identity: AgeIdentity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: identity.sourceIcon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.displayName)
                Text(identity.recipient.encoding)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
