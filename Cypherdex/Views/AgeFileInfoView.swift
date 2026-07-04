import SwiftUI
import CypherdexCore

/// A compact, read-only summary of an inspected age file — the same information
/// `age-inspect` reports: armor, recipient types, post-quantum status, and a
/// byte breakdown. Shown when a `.age` file or armored text is loaded to decrypt.
struct AgeFileInfoView: View {
    let info: AgeFileInfo

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.doc")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(info.summary)
                        .font(.callout.weight(.medium))
                    if info.isArmored {
                        Text("ASCII-armored")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if !info.isPassphrase {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(info.recipientCounts.enumerated()), id: \.offset) { _, entry in
                            Label {
                                Text(entry.count > 1 ? "\(entry.count) × \(entry.kind.label)" : entry.kind.label)
                            } icon: {
                                Image(systemName: entry.kind.systemImage)
                            }
                            .font(.caption)
                        }
                    }
                }

                if info.postQuantum != .unknown {
                    Label(
                        info.postQuantum == .yes ? "Post-quantum secure" : "Not post-quantum secure",
                        systemImage: info.postQuantum == .yes ? "shield.lefthalf.filled" : "shield.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let sizes = info.sizes {
                    Divider()
                    sizeBreakdown(sizes)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func sizeBreakdown(_ sizes: AgeFileInfo.Sizes) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            sizeRow("Header", sizes.header)
            if info.isArmored { sizeRow("Armor overhead", sizes.armorOverhead) }
            sizeRow("Encryption overhead", sizes.encryptionOverhead)
            sizeRow("Payload", sizes.payload)
            sizeRow("Total", sizes.total, emphasized: true)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func sizeRow(_ label: LocalizedStringKey, _ bytes: Int, emphasized: Bool = false) -> some View {
        GridRow {
            Text(label)
            Text(byteCount(bytes))
                .gridColumnAlignment(.trailing)
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
