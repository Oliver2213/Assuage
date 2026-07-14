import SwiftUI
import AssuageCore

/// One row in the People list: a person's name and first email, with capability
/// chips summarizing what we hold for them.
struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.isEmpty ? "Unnamed contact" : person.name)
                    .font(.headline)
                if let email = person.emails.first {
                    Text(email.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// The capability chips: a plain age key, post-quantum, SSH, a note verifier key,
    /// and a forge link we could fetch keys from.
    private var chips: [String] {
        var chips: [String] = []
        if person.ageRecipients.contains(where: { !$0.isPostQuantum }) { chips.append("Age") }
        if !person.postQuantumRecipients.isEmpty { chips.append("PQ") }
        if !person.sshRecipients.isEmpty { chips.append("SSH") }
        if !person.verifierKeys.isEmpty { chips.append("Verifier") }
        if !person.forgeURLs.isEmpty { chips.append("Link") }
        return chips
    }
}
