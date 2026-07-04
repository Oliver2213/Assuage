import SwiftUI

/// The review area shown once a file is parsed: a summary line and one editable
/// row per key. The summary is composed from `Text` segments with automatic
/// inflection so each clause is localizable and pluralizes per language.
struct ImportReviewList: View {
    @Binding var drafts: [ImportKeyDraft]
    let duplicatesRemoved: Int

    private var selectedCount: Int { drafts.filter(\.include).count }
    private var existingCount: Int { drafts.filter(\.alreadyExists).count }

    /// "3 of 4 keys selected · 1 already in your keychain · 2 duplicates removed".
    private var summary: Text {
        var summary = Text("\(selectedCount) of ^[\(drafts.count) key](inflect: true) selected")
        if existingCount > 0 {
            summary = summary + Text(" · ") + Text("\(existingCount) already in your keychain")
        }
        if duplicatesRemoved > 0 {
            summary = summary + Text(" · ") + Text("^[\(duplicatesRemoved) duplicate](inflect: true) removed")
        }
        return summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach($drafts) { $draft in
                    ImportKeyRow(draft: $draft)
                }
            }
            .frame(minHeight: 140, maxHeight: 360)
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
