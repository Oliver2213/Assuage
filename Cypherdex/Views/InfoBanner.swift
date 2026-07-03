import SwiftUI

/// A subtle explanatory banner. Accepts Markdown.
struct InfoBanner: View {
    let markdown: LocalizedStringKey

    init(_ markdown: LocalizedStringKey) {
        self.markdown = markdown
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(markdown)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}
