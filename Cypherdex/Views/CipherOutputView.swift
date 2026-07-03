import SwiftUI
import AppKit

/// The result of an encrypt or decrypt operation for display.
enum CryptoOutput: Equatable {
    case text(String)
    case binary(Data)
}

/// Shows a crypto result: selectable text with Copy (and optional Save), or a
/// binary blob with a size read-out and Save.
struct CipherOutputView: View {
    let title: LocalizedStringKey
    let output: CryptoOutput
    let binarySaveName: String
    var allowsTextSave = false
    var textSaveName = "message.age"
    var font: Font = .body.monospaced()

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                switch output {
                case .text(let text):
                    Text(text)
                        .font(font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("Copy", systemImage: "doc.on.doc") { copyToPasteboard(text) }
                        if allowsTextSave {
                            Button("Save…", systemImage: "square.and.arrow.down") {
                                SavePanel.save(text: text, suggestedName: textSaveName)
                            }
                        }
                        Spacer()
                    }
                case .binary(let data):
                    HStack {
                        Text("\(ByteFormatting.size(Int64(data.count))) — binary age file.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save…", systemImage: "square.and.arrow.down") {
                            SavePanel.save(data, suggestedName: binarySaveName)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
