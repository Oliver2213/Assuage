import SwiftUI
import AppKit
import AssuageCore

/// The detail pane for a selected contact. Leads with what you can actually do with
/// them — encrypt, encrypt post-quantum, verify their signed notes — then the finer
/// breakdown (key counts, forge links) below.
struct PersonDetail: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let person: Person
    /// Open the key editor for this contact.
    var onEdit: () -> Void
    /// Start encrypting text or files to this contact.
    var onEncrypt: (ComposeScope) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                capabilities
                breakdown
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(person.name.isEmpty ? "Contact" : person.name)
        .toolbar {
            Menu {
                Button("Text…", systemImage: "text.alignleft") { onEncrypt(.text) }
                Button("Files…", systemImage: "folder") { onEncrypt(.files) }
            } label: {
                Label("Encrypt to \(person.name.isEmpty ? "Contact" : person.name)", systemImage: "lock")
            }
            .disabled(!person.canEncrypt)
            if case .contact(let id) = person.source {
                Button("Open in Contacts", systemImage: "person.crop.circle") { openInContacts(id) }
            }
            Button("Edit Keys…", systemImage: "pencil", action: onEdit)
        }
    }

    private func openInContacts(_ identifier: String) {
        if let url = URL(string: "addressbook://\(identifier)") { NSWorkspace.shared.open(url) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.isEmpty ? "Unnamed contact" : person.name)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let email = person.emails.first {
                    Text(email.address).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Capabilities

    private var capabilities: some View {
        GroupBox("What you can do") {
            VStack(spacing: 0) {
                capabilityRow("Encrypt to this contact", enabled: person.canEncrypt,
                              keyDescription: "an age or SSH public key")
                Divider()
                capabilityRow("Encrypt post-quantum", enabled: person.canEncryptPostQuantum,
                              keyDescription: "a post-quantum age key")
                Divider()
                capabilityRow("Verify their signed notes", enabled: person.canVerifyNotes,
                              keyDescription: "a note verifier key")
            }
            .padding(.vertical, 2)
        }
    }

    /// A yes/no capability. The symbol shape and the trailing word carry the state, so
    /// it reads without relying on color; the explanation rides along as a tooltip. The
    /// decorative icon is hidden, so combining the children leaves VoiceOver reading just
    /// the title and its Yes/No — e.g. "Encrypt to this contact, Yes".
    private func capabilityRow(_ title: LocalizedStringKey, enabled: Bool, keyDescription: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(iconStyle(enabled))
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(enabled ? "Yes" : "No")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .help(enabled
              ? "They have \(keyDescription) associated with their contact card."
              : "They don’t have \(keyDescription) associated with their contact card.")
    }

    /// Colour the symbol with the accent for "yes" and a hierarchical grey for "no" —
    /// both adaptive, no hardcoded green. When the user asks not to differentiate by
    /// colour, drop it entirely and lean on the symbol shape and word.
    private func iconStyle(_ enabled: Bool) -> AnyShapeStyle {
        if differentiateWithoutColor { return AnyShapeStyle(.secondary) }
        return enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    // MARK: Breakdown

    private var breakdown: some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 8) {
                if keyCounts.isEmpty {
                    Text("No keys stored for this contact yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(keyCounts, id: \.label) { row in
                        LabeledContent(row.label, value: "\(row.count)")
                    }
                }
                if !person.forgeURLs.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Forge links")
                            .foregroundStyle(.secondary)
                        ForEach(person.forgeURLs, id: \.self) { url in
                            Link(CodeForgeKeys.account(from: url), destination: url)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !person.revocationLists.isEmpty {
                    Divider()
                    LabeledContent("Revocation lists", value: "\(person.revocationLists.count)")
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Key counts by type, only the non-zero ones. Age here means non-PQ age keys, so
    /// they don't double-count with the post-quantum row.
    private var keyCounts: [(label: String, count: Int)] {
        let plainAge = person.ageRecipients.count - person.postQuantumRecipients.count
        return [
            ("Age keys", plainAge),
            ("Post-quantum keys", person.postQuantumRecipients.count),
            ("SSH keys", person.sshRecipients.count),
            ("Verifier keys", person.verifierKeys.count),
        ].filter { $0.1 > 0 }
    }
}
