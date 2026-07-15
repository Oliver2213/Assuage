import SwiftUI

/// Add recipients by fetching a code-forge account's public keys from its `.keys`
/// page. Hands the profile it fetched from, plus the parsed recipients, back to the
/// caller via `onAdd` (the profile lets the caller record where the keys came from).
struct RecipientURLSheet: View {
    let onAdd: (_ profile: String, _ recipients: [NamedRecipient]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var isFetching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add from a Code Forge")
                .font(.title2.bold())

            Text("Paste the URL to a code-forge profile — such as GitHub, Codeberg, or SourceHut. Assuage fetches that account’s public keys from its `.keys` endpoint.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("github.com/username", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(fetch)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isFetching)
                if isFetching {
                    ProgressView().controlSize(.small)
                }
                Button("Add", action: fetch)
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func fetch() {
        let query = input
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty, !isFetching else { return }
        isFetching = true
        errorMessage = nil
        Task {
            do {
                let recipients = try await CodeForgeKeys.fetch(fromProfile: query)
                guard !recipients.isEmpty else {
                    errorMessage = String(localized: "No age or SSH public keys found at that URL.")
                    isFetching = false
                    return
                }
                onAdd(query, recipients)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isFetching = false
            }
        }
    }
}
