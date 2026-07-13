import SwiftUI

/// The Text panel: an Encrypt / Decrypt sub-tab over the text-scoped compose views.
struct TextView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            OperationPicker()
            switch model.operation {
            case .encrypt: EncryptView(scope: .text)
            case .decrypt: DecryptView(scope: .text)
            }
        }
        .navigationTitle("Text")
    }
}
