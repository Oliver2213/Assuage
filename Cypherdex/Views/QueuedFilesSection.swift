import SwiftUI
import UniformTypeIdentifiers

/// A "Files" box: a queue of files with add / drop / remove, and a run button
/// that performs the encrypt or decrypt on the queue.
struct QueuedFilesSection: View {
    let caption: LocalizedStringKey
    @Binding var files: [URL]
    let runVerb: String
    let runIcon: String
    let dropPrompt: String
    let dropIcon: String
    let isRunEnabled: Bool
    let onRun: () -> Void
    /// Optional success line shown under the controls.
    var status: String?

    @State private var showImporter = false

    var body: some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 10) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                QueuedFilesList(files: $files)

                HStack {
                    Button("Add Files…", systemImage: "plus") { showImporter = true }
                    Button("\(runVerb) \(files.count) File\(files.count == 1 ? "" : "s")", systemImage: runIcon, action: onRun)
                        .disabled(files.isEmpty || !isRunEnabled)
                    Spacer()
                }

                FileWell(prompt: dropPrompt, systemImage: dropIcon) { urls in
                    files.append(contentsOf: urls)
                }

                if let status {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(4)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files.append(contentsOf: urls) }
        }
    }
}
