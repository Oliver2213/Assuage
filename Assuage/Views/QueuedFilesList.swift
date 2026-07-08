import SwiftUI

/// A compact, removable list of queued file URLs.
struct QueuedFilesList: View {
    @Binding var files: [URL]

    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(files, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove \(url.lastPathComponent)", systemImage: "xmark.circle.fill") {
                            files.removeAll { $0 == url }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
        }
    }
}
