import SwiftUI

/// A row in a detail list: a symbol, a title, a value, and a line under it.
struct InfoRow: View {
    let symbol: String
    let title: String
    var detail: String = ""
    var note: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            #if !os(tvOS)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            #endif
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
