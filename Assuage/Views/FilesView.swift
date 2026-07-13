import SwiftUI

/// The Files panel: an Encrypt / Decrypt sub-tab over the file-scoped compose views.
struct FilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            OperationPicker()
            switch model.operation {
            case .encrypt: EncryptView(scope: .files)
            case .decrypt: DecryptView(scope: .files)
            }
        }
        .navigationTitle("Files")
    }
}
