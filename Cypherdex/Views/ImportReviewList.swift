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
    /// Each clause is its own `Text` so it stays localizable, joined with `·`
    /// via `Text` interpolation (the modern replacement for `Text` concatenation).
    private var summary: Text {
        var clauses = [Text("\(selectedCount) of ^[\(drafts.count) key](inflect: true) selected")]
        if existingCount > 0 {
            clauses.append(Text("\(existingCount) already in your keychain"))
        }
        if duplicatesRemoved > 0 {
            clauses.append(Text("^[\(duplicatesRemoved) duplicate](inflect: true) removed"))
        }
        return clauses.dropFirst().reduce(clauses[0]) { Text("\($0) · \($1)") }
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
