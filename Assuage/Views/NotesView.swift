import SwiftUI

/// The Notes panel: a Sign / Verify sub-tab over C2SP signed notes.
struct NotesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Operation", selection: $model.noteOperation) {
                ForEach(AppModel.NoteOperation.allCases) { operation in
                    Text(operation.title).tag(operation)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch model.noteOperation {
            case .sign: SignView()
            case .verify: VerifyView()
            }
        }
        .navigationTitle("Notes")
    }
}
