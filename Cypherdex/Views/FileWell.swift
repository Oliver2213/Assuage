import SwiftUI

/// A dashed drop target for files, with drag highlighting.
struct FileWell: View {
    let prompt: String
    let systemImage: String
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.title2)
                    Text(prompt)
                        .font(.callout)
                }
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            }
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return true
            } isTargeted: { isTargeted = $0 }
            .accessibilityElement()
            .accessibilityLabel(prompt)
    }
}
