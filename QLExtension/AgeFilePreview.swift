import SwiftUI
import AssuageCore

/// The Quick Look preview body: the file name over the shared `AgeFileInfoView`.
/// `decryptability` is always omitted here — the extension holds no keys.
struct AgeFilePreview: View {
    let info: AgeFileInfo
    let filename: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                AgeFileInfoView(info: info)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
