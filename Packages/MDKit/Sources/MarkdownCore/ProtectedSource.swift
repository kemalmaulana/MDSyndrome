/// Source text with math spans swapped for placeholders, so cmark never
/// sees `$…$` content (where `*`, `_`, `\` and `|` would be misread as markdown).
///
/// Invariant: `text` has exactly the same number of lines as the original,
/// so cmark's source line numbers still point at the user's text.
public struct ProtectedSource: Sendable {
    public struct Span: Hashable, Sendable {
        public let latex: String
        public let display: Bool
        /// The exact original text, delimiters included. Used to undo the
        /// replacement inside code, where math must stay literal.
        public let original: String
    }

    public let text: String
    public let spans: [Span]

    static let open: Character = "\u{E000}"
    static let close: Character = "\u{E001}"

    static func placeholder(_ index: Int) -> String {
        "\(open)\(index)\(close)"
    }

    /// Splits a cmark text literal into text and math inlines.
    public func inlines(from literal: String) -> [Inline] {
        guard !spans.isEmpty, literal.contains(Self.open) else { return [.text(literal)] }
        var result: [Inline] = []
        var buffer = ""
        forEachPlaceholder(in: literal, text: { buffer.append($0) }, math: { span in
            if !buffer.isEmpty { result.append(.text(buffer)); buffer = "" }
            result.append(.math(latex: span.latex, display: span.display))
        })
        if !buffer.isEmpty { result.append(.text(buffer)) }
        return result
    }

    /// Puts the original math source back (for code spans/blocks and HTML).
    public func restore(_ literal: String) -> String {
        guard !spans.isEmpty, literal.contains(Self.open) else { return literal }
        var out = ""
        forEachPlaceholder(in: literal, text: { out.append($0) }, math: { out += $0.original })
        return out
    }

    private func forEachPlaceholder(in literal: String, text: (Character) -> Void, math: (Span) -> Void) {
        var i = literal.startIndex
        while i < literal.endIndex {
            let c = literal[i]
            if c == Self.open,
               let close = literal[i...].firstIndex(of: Self.close),
               let index = Int(literal[literal.index(after: i)..<close]),
               spans.indices.contains(index) {
                math(spans[index])
                i = literal.index(after: close)
            } else {
                text(c)
                i = literal.index(after: i)
            }
        }
    }
}
