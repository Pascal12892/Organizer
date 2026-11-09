import Foundation
import Markdown

/// Ein Markdown-Dokument als Liste von Blöcken, die die App nativ in SwiftUI darstellt.
/// Inline-Formatierung steckt in `AttributedString` (fett, kursiv, Code, Links).
public struct MarkdownContent: Sendable, Hashable {
    public let blocks: [MarkdownBlock]

    /// - Parameter firstLine: 0-basierte Zeile in der Datei, in der `markdown` beginnt.
    ///   Damit kennen Checkboxen ihre Zeile in der Datei und lassen sich abhaken.
    public init(markdown: String, firstLine: Int = 0) {
        let document = Document(parsing: WikiLinks.rewrite(markdown))
        blocks = MarkdownConverter.blocks(from: document.children, lineOffset: firstLine)
    }
}

public enum MarkdownBlock: Sendable, Hashable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case list(MarkdownList)
    case quote([MarkdownBlock])
    case code(language: String?, code: String)
    case table(header: [AttributedString], rows: [[AttributedString]])
    case divider
}

public struct MarkdownList: Sendable, Hashable {
    public var ordered: Bool
    public var start: Int
    public var items: [MarkdownListItem]
}

public struct MarkdownListItem: Sendable, Hashable {
    /// `nil` = keine Checkbox, sonst abgehakt ja/nein.
    public var checkbox: Bool?
    /// 0-basierte Zeile in der Datei (nur bei Checkboxen gesetzt).
    public var sourceLine: Int? = nil
    public var blocks: [MarkdownBlock]
}

enum MarkdownConverter {

    static func blocks(from children: some Sequence<any Markup>, lineOffset: Int) -> [MarkdownBlock] {
        children.compactMap { block(from: $0, lineOffset: lineOffset) }
    }

    static func block(from markup: any Markup, lineOffset: Int) -> MarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inline(heading.inlineChildren))
        case let paragraph as Paragraph:
            return .paragraph(inline(paragraph.inlineChildren))
        case let list as UnorderedList:
            return .list(MarkdownList(ordered: false, start: 1, items: list.listItems.map { listItem($0, lineOffset: lineOffset) }))
        case let list as OrderedList:
            return .list(MarkdownList(ordered: true, start: Int(list.startIndex), items: list.listItems.map { listItem($0, lineOffset: lineOffset) }))
        case let quote as BlockQuote:
            return .quote(blocks(from: quote.children, lineOffset: lineOffset))
        case let code as CodeBlock:
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
            return .code(language: language, code: text)
        case is ThematicBreak:
            return .divider
        case let table as Markdown.Table:
            let header: [AttributedString] = table.head.cells.map { inline($0.inlineChildren) }
            let rows: [[AttributedString]] = table.body.rows.map { row in
                row.cells.map { inline($0.inlineChildren) }
            }
            return .table(header: header, rows: rows)
        case let html as HTMLBlock:
            return .code(language: "html", code: html.rawHTML.trimmingCharacters(in: .newlines))
        default:
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .paragraph(AttributedString(text))
        }
    }

    static func listItem(_ item: ListItem, lineOffset: Int) -> MarkdownListItem {
        let checkbox: Bool? = switch item.checkbox {
        case .checked: true
        case .unchecked: false
        case nil: nil
        }
        let line = checkbox != nil ? item.range.map { lineOffset + $0.lowerBound.line - 1 } : nil
        return MarkdownListItem(checkbox: checkbox, sourceLine: line, blocks: blocks(from: item.children, lineOffset: lineOffset))
    }

    static func inline(
        _ children: some Sequence<any InlineMarkup>,
        intent: InlinePresentationIntent = [],
        link: URL? = nil
    ) -> AttributedString {
        var result = AttributedString()
        for child in children {
            result += inlineNode(child, intent: intent, link: link)
        }
        return result
    }

    static func inlineNode(_ node: any InlineMarkup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        switch node {
        case let text as Markdown.Text:
            return styled(text.string, intent, link)
        case let emphasis as Emphasis:
            return inline(emphasis.inlineChildren, intent: intent.union(.emphasized), link: link)
        case let strong as Strong:
            return inline(strong.inlineChildren, intent: intent.union(.stronglyEmphasized), link: link)
        case let strike as Strikethrough:
            return inline(strike.inlineChildren, intent: intent.union(.strikethrough), link: link)
        case let code as InlineCode:
            return styled(code.code, intent.union(.code), link)
        case let markdownLink as Markdown.Link:
            return inline(markdownLink.inlineChildren, intent: intent, link: url(forDestination: markdownLink.destination) ?? link)
        case let image as Markdown.Image:
            // Bilder zeigt Phase 1 noch nicht an, nur ihren Alternativtext.
            let alt = image.plainText.isEmpty ? (image.source ?? "Bild") : image.plainText
            return styled(alt, intent.union(.emphasized), link)
        case is SoftBreak:
            return styled(" ", intent, link)
        case is LineBreak:
            return styled("\n", intent, link)
        case let html as InlineHTML:
            return styled(html.rawHTML, intent, link)
        default:
            return styled(node.plainText, intent, link)
        }
    }

    /// Relative Links auf `.md`-Dateien werden wie Wikilinks behandelt.
    static func url(forDestination destination: String?) -> URL? {
        guard let destination, !destination.isEmpty else { return nil }
        if let url = URL(string: destination), url.scheme != nil { return url }
        let decoded = destination.removingPercentEncoding ?? destination
        if decoded.lowercased().hasSuffix(".md") || !decoded.contains(".") {
            return WikiLinks.url(forTarget: decoded)
        }
        return URL(string: destination)
    }

    static func styled(_ string: String, _ intent: InlinePresentationIntent, _ link: URL?) -> AttributedString {
        var text = AttributedString(string)
        if !intent.isEmpty { text.inlinePresentationIntent = intent }
        if let link { text.link = link }
        return text
    }
}
