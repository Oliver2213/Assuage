import SwiftUI

/// The Encrypt / Decrypt segmented control shown atop the Files and Text panels,
/// bound to the shared `operation`. ⌘⇧1 / ⌘⇧2 switch it from the menu bar.
struct OperationPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Operation", selection: $model.operation) {
            ForEach(AppModel.Operation.allCases) { operation in
                Text(operation.title).tag(operation)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
