import HubCore
import SwiftUI

/// Stellt Markdown mit nativen SwiftUI-Elementen und Systemschriften dar.
struct MarkdownView: View {
    let content: MarkdownContent

    var body: some View {
        MarkdownBlocksView(blocks: content.blocks)
            .textSelection(.enabled)
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 8 : 4)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let list):
            MarkdownListView(list: list)

        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: blocks)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.weight(.bold)
        case 2: .title2.weight(.bold)
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct MarkdownListView: View {
    let list: MarkdownList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, index: index)
                    MarkdownBlocksView(blocks: item.blocks)
                        .foregroundStyle(item.checkbox == true ? .secondary : .primary)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index: Int) -> some View {
        if let checked = item.checkbox {
            // Phase 4 macht die Checkboxen anklickbar.
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .imageScale(.large)
                .accessibilityLabel(checked ? "Erledigt" : "Offen")
        } else if list.ordered {
            Text("\(list.start + index).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(.body.monospaced())
                    .fixedSize()
            }
            .scrollIndicators(.automatic)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MarkdownTableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.headline)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview("Hell") {
    ScrollView {
        MarkdownView(content: MarkdownContent(markdown: PreviewData.markdownSample))
            .padding(24)
    }
    .frame(width: 560, height: 700)
}

#Preview("Dunkel") {
    ScrollView {
        MarkdownView(content: MarkdownContent(markdown: PreviewData.markdownSample))
            .padding(24)
    }
    .frame(width: 560, height: 700)
    .preferredColorScheme(.dark)
}
