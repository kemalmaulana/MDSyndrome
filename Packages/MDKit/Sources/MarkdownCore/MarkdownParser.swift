import cmark_gfm
import cmark_gfm_extensions

typealias CMarkNode = UnsafeMutablePointer<cmark_node>

public enum MarkdownParser {
    /// cmark-gfm's extension registry is process-global; register exactly once.
    private static let registerExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    public static func parse(_ text: String, options: MarkdownOptions = .default) -> MarkdownDocument {
        _ = registerExtensions
        let protected = ProtectedSource(text: text, spans: [])

        var flags = CMARK_OPT_SOURCEPOS
        if options.footnotes { flags |= CMARK_OPT_FOOTNOTES }
        if options.smartPunctuation { flags |= CMARK_OPT_SMART }

        guard let parser = cmark_parser_new(flags) else { return MarkdownDocument(blocks: []) }
        defer { cmark_parser_free(parser) }

        var extensions: [String] = []
        if options.tables { extensions.append("table") }
        if options.strikethrough { extensions.append("strikethrough") }
        if options.autolinks { extensions.append("autolink") }
        if options.taskLists { extensions.append("tasklist") }
        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        let source = protected.text
        cmark_parser_feed(parser, source, source.utf8.count)
        guard let root = cmark_parser_finish(parser) else { return MarkdownDocument(blocks: []) }
        defer { cmark_node_free(root) }

        var converter = NodeConverter(
            originalLines: text.split(separator: "\n", omittingEmptySubsequences: false),
            math: protected,
            hardBreaks: options.hardBreaks
        )
        return MarkdownDocument(blocks: converter.blocks(under: root, depth: 0))
    }
}

/// Walks the cmark tree and builds the owned, Sendable AST.
struct NodeConverter {
    /// Containers and inline spans nested deeper than this are flattened to
    /// plain text. Parsing runs on cooperative-pool threads with small stacks,
    /// and the preview's view tree mirrors this nesting, so recursion must stay
    /// shallow even for hostile input like 5,000 nested `>`.
    static let maxDepth = 32

    let originalLines: [Substring]
    let math: ProtectedSource
    /// CMARK_OPT_HARDBREAKS only affects cmark's own renderers; the tree still
    /// has soft breaks, so the conversion is done here.
    let hardBreaks: Bool
    private var footnoteCount = 0

    init(originalLines: [Substring], math: ProtectedSource, hardBreaks: Bool) {
        self.originalLines = originalLines
        self.math = math
        self.hardBreaks = hardBreaks
    }

    mutating func blocks(under parent: CMarkNode, depth: Int) -> [Block] {
        var result: [Block] = []
        var seen: [UInt64: Int] = [:]
        var child = cmark_node_first_child(parent)
        while let node = child {
            if let kind = blockKind(node, depth: depth) {
                let lines = sourceLines(node)
                let id = makeID(kind: kind, lines: lines, seen: &seen)
                result.append(Block(id: id, lines: lines, kind: kind))
            }
            child = cmark_node_next(node)
        }
        return result
    }

    private mutating func blockKind(_ node: CMarkNode, depth: Int) -> Block.Kind? {
        let type = cmark_node_get_type(node)
        let isContainer = type == CMARK_NODE_BLOCK_QUOTE || type == CMARK_NODE_LIST || type == CMARK_NODE_FOOTNOTE_DEFINITION
        if isContainer, depth >= Self.maxDepth {
            return .paragraph([.text(flattenedText(node))])
        }
        switch type {
        case CMARK_NODE_PARAGRAPH:
            let content = inlines(under: node, depth: 0)
            if case .math(let latex, true)? = content.onlyNonWhitespace { return .mathBlock(latex: latex) }
            return .paragraph(content)
        case CMARK_NODE_HEADING:
            return .heading(level: Int(cmark_node_get_heading_level(node)), content: inlines(under: node, depth: 0))
        case CMARK_NODE_BLOCK_QUOTE:
            return .blockQuote(blocks(under: node, depth: depth + 1))
        case CMARK_NODE_LIST:
            return .list(list(node, depth: depth))
        case CMARK_NODE_CODE_BLOCK:
            var code = math.restore(string(cmark_node_get_literal(node)))
            if code.hasSuffix("\n") { code.removeLast() }
            let info = string(cmark_node_get_fence_info(node))
            let language = info.split(separator: " ").first.map(String.init)
            if language?.lowercased() == "math" { return .mathBlock(latex: code) }
            return .codeBlock(language: language, code: code)
        case CMARK_NODE_HTML_BLOCK:
            var html = math.restore(string(cmark_node_get_literal(node)))
            if html.hasSuffix("\n") { html.removeLast() }
            return .htmlBlock(html)
        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak
        case CMARK_NODE_FOOTNOTE_DEFINITION:
            // cmark-gfm appends referenced definitions to the end of the
            // document in reference order, so position == reference index.
            footnoteCount += 1
            return .footnoteDefinition(index: footnoteCount, label: string(cmark_node_get_literal(node)), blocks: blocks(under: node, depth: depth + 1))
        default:
            if typeString(node) == "table" { return .table(table(node)) }
            return nil
        }
    }

    private mutating func list(_ node: CMarkNode, depth: Int) -> ListBlock {
        let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
        var items: [ListItem] = []
        var seen: [UInt64: Int] = [:]
        var child = cmark_node_first_child(node)
        while let item = child {
            let lines = sourceLines(item)
            let task: TaskState? = typeString(item) == "tasklist"
                ? (cmark_gfm_extensions_get_tasklist_item_checked(item) ? .checked : .unchecked)
                : nil
            let content = blocks(under: item, depth: depth + 1)
            items.append(ListItem(id: makeID(tag: "item", lines: lines, seen: &seen), lines: lines, task: task, blocks: content))
            child = cmark_node_next(item)
        }
        return ListBlock(
            ordered: ordered,
            start: ordered ? Int(cmark_node_get_list_start(node)) : 1,
            tight: cmark_node_get_list_tight(node) != 0,
            items: items
        )
    }

    private mutating func table(_ node: CMarkNode) -> TableBlock {
        let columns = Int(cmark_gfm_extensions_get_table_columns(node))
        var alignments: [TableBlock.Alignment] = []
        if let raw = cmark_gfm_extensions_get_table_alignments(node) {
            for i in 0..<columns {
                switch UInt8(raw[i]) {
                case UInt8(ascii: "l"): alignments.append(.left)
                case UInt8(ascii: "c"): alignments.append(.center)
                case UInt8(ascii: "r"): alignments.append(.right)
                default: alignments.append(.none)
                }
            }
        }
        var header: [[Inline]] = []
        var rows: [[[Inline]]] = []
        var rowNode = cmark_node_first_child(node)
        while let row = rowNode {
            var cells: [[Inline]] = []
            var cellNode = cmark_node_first_child(row)
            while let cell = cellNode {
                cells.append(inlines(under: cell, depth: 0))
                cellNode = cmark_node_next(cell)
            }
            cells = Array(cells.prefix(columns)) + Array(repeating: [], count: max(0, columns - cells.count))
            if typeString(row) == "table_header" { header = cells } else { rows.append(cells) }
            rowNode = cmark_node_next(row)
        }
        return TableBlock(alignments: alignments, header: header, rows: rows)
    }

    private func inlines(under parent: CMarkNode, depth: Int) -> [Inline] {
        if depth >= Self.maxDepth { return [.text(flattenedText(parent))] }
        var result: [Inline] = []
        var child = cmark_node_first_child(parent)
        while let node = child {
            result.append(contentsOf: inline(node, depth: depth))
            child = cmark_node_next(node)
        }
        return result.mergingAdjacentText()
    }

    private func inline(_ node: CMarkNode, depth: Int) -> [Inline] {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT:
            return math.inlines(from: string(cmark_node_get_literal(node)))
        case CMARK_NODE_SOFTBREAK:
            return [hardBreaks ? .lineBreak : .softBreak]
        case CMARK_NODE_LINEBREAK:
            return [.lineBreak]
        case CMARK_NODE_CODE:
            return [.code(math.restore(string(cmark_node_get_literal(node))))]
        case CMARK_NODE_HTML_INLINE:
            return [.html(math.restore(string(cmark_node_get_literal(node))))]
        case CMARK_NODE_EMPH:
            return [.emphasis(inlines(under: node, depth: depth + 1))]
        case CMARK_NODE_STRONG:
            return [.strong(inlines(under: node, depth: depth + 1))]
        case CMARK_NODE_LINK:
            return [.link(destination: string(cmark_node_get_url(node)), title: nonEmpty(cmark_node_get_title(node)), content: inlines(under: node, depth: depth + 1))]
        case CMARK_NODE_IMAGE:
            return [.image(source: string(cmark_node_get_url(node)), title: nonEmpty(cmark_node_get_title(node)), alt: Inline.plainText(inlines(under: node, depth: depth + 1)))]
        case CMARK_NODE_FOOTNOTE_REFERENCE:
            return [.footnoteReference(index: Int(string(cmark_node_get_literal(node))) ?? 0)]
        default:
            if typeString(node) == "strikethrough" { return [.strikethrough(inlines(under: node, depth: depth + 1))] }
            return inlines(under: node, depth: depth + 1)
        }
    }

    // MARK: - Helpers

    /// All text under `node`, collected with cmark's iterator (no recursion).
    private func flattenedText(_ node: CMarkNode) -> String {
        guard let iterator = cmark_iter_new(node) else { return "" }
        defer { cmark_iter_free(iterator) }
        var text = ""
        while true {
            let event = cmark_iter_next(iterator)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER, let current = cmark_iter_get_node(iterator) else { continue }
            switch cmark_node_get_type(current) {
            case CMARK_NODE_TEXT, CMARK_NODE_CODE, CMARK_NODE_CODE_BLOCK:
                text += math.restore(string(cmark_node_get_literal(current)))
            case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
                text += " "
            case CMARK_NODE_PARAGRAPH, CMARK_NODE_HEADING:
                if !text.isEmpty, text.last != " " { text += " " }
            default:
                break
            }
        }
        return text
    }

    private func sourceLines(_ node: CMarkNode) -> SourceLines {
        let start = Int(cmark_node_get_start_line(node))
        var end = Int(cmark_node_get_end_line(node))
        // cmark reports "ends at column 0 of line N" for blocks that end at the
        // close of line N-1 (lists, items, indented code).
        if cmark_node_get_end_column(node) == 0, end > start { end -= 1 }
        return SourceLines(start: start, end: end)
    }

    private func makeID(kind: Block.Kind, lines: SourceLines, seen: inout [UInt64: Int]) -> BlockID {
        makeID(tag: tag(kind), lines: lines, seen: &seen)
    }

    private func makeID(tag: String, lines: SourceLines, seen: inout [UInt64: Int]) -> BlockID {
        var hash = StableHash()
        hash.combine(tag)
        let lower = max(0, lines.start - 1)
        let upper = min(originalLines.count, lines.end)
        if lower < upper {
            for line in originalLines[lower..<upper] {
                hash.combine(line)
                hash.combine("\n")
            }
        }
        let base = hash.value
        let duplicate = seen[base, default: 0]
        seen[base] = duplicate + 1
        hash.combine(duplicate)
        return BlockID(hash.value)
    }

    private func tag(_ kind: Block.Kind) -> String {
        switch kind {
        case .heading: "h"
        case .paragraph: "p"
        case .blockQuote: "q"
        case .list: "l"
        case .codeBlock: "c"
        case .thematicBreak: "hr"
        case .htmlBlock: "html"
        case .table: "t"
        case .mathBlock: "m"
        case .footnoteDefinition: "fn"
        }
    }

    private func typeString(_ node: CMarkNode) -> String {
        string(cmark_node_get_type_string(node))
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }

    private func nonEmpty(_ pointer: UnsafePointer<CChar>?) -> String? {
        let s = string(pointer)
        return s.isEmpty ? nil : s
    }
}

extension Array where Element == Inline {
    func mergingAdjacentText() -> [Inline] {
        var result: [Inline] = []
        for inline in self {
            if case .text(let next) = inline, case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + next)
            } else {
                result.append(inline)
            }
        }
        return result
    }

    /// The single inline left after dropping whitespace-only text, if exactly one remains.
    public var onlyNonWhitespace: Inline? {
        let meaningful = filter {
            if case .text(let s) = $0 { return !s.allSatisfy(\.isWhitespace) }
            if case .softBreak = $0 { return false }
            return true
        }
        return meaningful.count == 1 ? meaningful[0] : nil
    }
}
