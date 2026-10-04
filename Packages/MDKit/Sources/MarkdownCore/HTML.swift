import Foundation

/// One HTML tag such as `<a href="x">`, `</b>` or `<br/>`.
public struct HTMLTag: Hashable, Sendable {
    /// Lowercased element name.
    public let name: String
    public let isClosing: Bool
    public let isSelfClosing: Bool
    /// Lowercased attribute names → entity-decoded values (`""` for valueless attributes like `open`).
    public let attributes: [String: String]

    static let voidElements: Set<String> = ["br", "img", "hr", "source", "wbr", "input", "meta", "link"]

    /// Parses exactly one tag. nil for comments, doctypes and anything that isn't a well-formed tag.
    public static func parse(_ raw: some StringProtocol) -> HTMLTag? {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("<"), raw.hasSuffix(">"), raw.count >= 3 else { return nil }
        var body = Substring(raw.dropFirst().dropLast())
        let isClosing = body.hasPrefix("/")
        if isClosing { body = body.dropFirst() }
        let name = body.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        guard let first = name.first, first.isLetter else { return nil }
        var rest = body.dropFirst(name.count)
        var isSelfClosing = false
        if rest.hasSuffix("/") {
            isSelfClosing = true
            rest = rest.dropLast()
        }
        let lowered = name.lowercased()
        return HTMLTag(
            name: lowered,
            isClosing: isClosing,
            isSelfClosing: isSelfClosing || voidElements.contains(lowered),
            attributes: isClosing ? [:] : parseAttributes(rest)
        )
    }

    private static func parseAttributes(_ text: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        var i = text.startIndex
        func skipSpaces() { while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) } }
        while true {
            skipSpaces()
            guard i < text.endIndex else { break }
            let nameStart = i
            while i < text.endIndex, !text[i].isWhitespace, text[i] != "=", text[i] != "/" { i = text.index(after: i) }
            let name = text[nameStart..<i].lowercased()
            guard !name.isEmpty else { i = text.index(after: i); continue }
            skipSpaces()
            var value = ""
            if i < text.endIndex, text[i] == "=" {
                i = text.index(after: i)
                skipSpaces()
                if i < text.endIndex, text[i] == "\"" || text[i] == "'" {
                    let quote = text[i]
                    let valueStart = text.index(after: i)
                    var j = valueStart
                    while j < text.endIndex, text[j] != quote { j = text.index(after: j) }
                    value = String(text[valueStart..<j])
                    i = j < text.endIndex ? text.index(after: j) : j
                } else {
                    let valueStart = i
                    while i < text.endIndex, !text[i].isWhitespace { i = text.index(after: i) }
                    value = String(text[valueStart..<i])
                }
            }
            attributes[name] = HTMLEntities.decode(value)
        }
        return attributes
    }
}

/// Decodes the HTML character references that show up in READMEs.
public enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "middot": "·", "bull": "•", "rarr": "→", "larr": "←", "uarr": "↑", "darr": "↓",
        "times": "×", "deg": "°", "laquo": "«", "raquo": "»", "ldquo": "“", "rdquo": "”",
        "lsquo": "‘", "rsquo": "’", "check": "✓", "hearts": "♥", "star": "☆",
    ]

    public static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semicolon = text[i...].prefix(12).firstIndex(of: ";") {
                let entity = text[text.index(after: i)..<semicolon]
                if let decoded = decodeEntity(entity) {
                    out += decoded
                    i = text.index(after: semicolon)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }

    private static func decodeEntity(_ entity: Substring) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if entity.hasPrefix("#") {
            return UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[String(entity)]
    }
}

/// Supported inline HTML (`<kbd>`, `<sub>`, `<b>`, `<a href>`, `<img>`, `<br>` …) turned into semantic inlines.
enum HTMLInline {
    /// Elements whose open/close pair wraps content.
    static let wrappers: Set<String> = ["a", "b", "strong", "i", "em", "u", "ins", "s", "del", "strike", "code", "kbd", "sub", "sup", "mark", "span", "small", "picture"]

    /// Rewrites matched tag pairs in a sibling run of inlines. Unmatched or unsupported tags stay `.html`.
    static func transform(_ inlines: [Inline]) -> [Inline] {
        guard inlines.contains(where: { if case .html = $0 { true } else { false } }) else { return inlines }
        var result: [Inline] = []
        var i = 0
        while i < inlines.count {
            guard case .html(let raw) = inlines[i], let tag = HTMLTag.parse(raw), !tag.isClosing else {
                result.append(inlines[i])
                i += 1
                continue
            }
            if tag.isSelfClosing {
                switch tag.name {
                case "br": result.append(.lineBreak)
                case "img":
                    let width = tag.attributes["width"].flatMap { Double($0.replacingOccurrences(of: "px", with: "")) }
                    result.append(.image(source: tag.attributes["src"] ?? "", title: tag.attributes["title"], alt: tag.attributes["alt"] ?? "", width: width))
                case "source": break   // <picture> sources: the <img> fallback is used
                default: result.append(inlines[i])
                }
                i += 1
                continue
            }
            guard wrappers.contains(tag.name), let close = matchingClose(for: tag.name, in: inlines, after: i) else {
                result.append(inlines[i])
                i += 1
                continue
            }
            let children = transform(Array(inlines[(i + 1)..<close]))
            result.append(contentsOf: wrap(children, in: tag))
            i = close + 1
        }
        return result.mergingAdjacentText()
    }

    private static func matchingClose(for name: String, in inlines: [Inline], after open: Int) -> Int? {
        var depth = 0
        for j in (open + 1)..<inlines.count {
            guard case .html(let raw) = inlines[j], let tag = HTMLTag.parse(raw), tag.name == name, !tag.isSelfClosing else { continue }
            if tag.isClosing {
                if depth == 0 { return j }
                depth -= 1
            } else {
                depth += 1
            }
        }
        return nil
    }

    private static func wrap(_ children: [Inline], in tag: HTMLTag) -> [Inline] {
        switch tag.name {
        case "b", "strong": [.strong(children)]
        case "i", "em": [.emphasis(children)]
        case "u", "ins": [.underline(children)]
        case "s", "del", "strike": [.strikethrough(children)]
        case "code": [.code(Inline.plainText(children))]
        case "kbd": [.keyboard(children)]
        case "sub": [.subscript(children)]
        case "sup": [.superscript(children)]
        case "mark": [.highlight(children)]
        case "a":
            if let href = tag.attributes["href"], !href.isEmpty {
                [.link(destination: href, title: tag.attributes["title"], content: children)]
            } else {
                children
            }
        default: children   // span, small, picture: transparent
        }
    }
}

/// A raw HTML block made only of simple layout tags (`<p align>`, `<h1>`, `<div>`, `<center>`)
/// and supported inline tags, converted to native paragraphs and headings.
/// Anything else is left as raw HTML.
enum HTMLBlock {
    struct Element: Equatable {
        /// 0 = paragraph, 1…6 = heading level.
        var level: Int
        var alignment: BlockAlignment
        var content: [Inline]
    }

    private static let blockElements: Set<String> = ["p", "div", "center", "h1", "h2", "h3", "h4", "h5", "h6"]
    private static let allowed = blockElements.union(HTMLInline.wrappers).union(["br", "img", "source"])

    /// nil when the block contains any unsupported tag. An empty array means "nothing visible" (e.g. only comments).
    static func convert(_ html: String) -> [Element]? {
        guard let tokens = tokenize(html) else { return nil }
        var elements: [Element] = []
        var alignments: [BlockAlignment] = [.leading]
        var current: Element?
        var loose: [Inline] = []

        func flushLoose() {
            let content = clean(loose)
            if !content.isEmpty { elements.append(Element(level: 0, alignment: alignments.last!, content: content)) }
            loose = []
        }
        func finishCurrent() {
            if var element = current {
                element.content = clean(element.content)
                if !element.content.isEmpty { elements.append(element) }
            }
            current = nil
        }

        for token in tokens {
            switch token {
            case .text(let text):
                if current != nil { current!.content.append(.text(text)) } else { loose.append(.text(text)) }
            case .tag(let raw, let tag):
                guard allowed.contains(tag.name) else { return nil }
                guard blockElements.contains(tag.name) else {
                    if current != nil { current!.content.append(.html(raw)) } else { loose.append(.html(raw)) }
                    continue
                }
                let alignment = alignment(of: tag) ?? alignments.last!
                switch (tag.name, tag.isClosing) {
                case ("div", false), ("center", false):
                    finishCurrent(); flushLoose()
                    alignments.append(tag.name == "center" ? .center : alignment)
                case ("div", true), ("center", true):
                    finishCurrent(); flushLoose()
                    if alignments.count > 1 { alignments.removeLast() }
                case (_, false):
                    finishCurrent(); flushLoose()
                    let level = tag.name.hasPrefix("h") ? Int(tag.name.dropFirst()) ?? 0 : 0
                    current = Element(level: level, alignment: alignment, content: [])
                case (_, true):
                    finishCurrent()
                }
            }
        }
        finishCurrent()
        flushLoose()
        return elements
    }

    /// Converts an HTML fragment with only inline tags (e.g. a `<summary>`) to inlines.
    static func inlines(fromFragment html: String) -> [Inline] {
        guard let tokens = tokenize(html) else { return [.text(html)] }
        let raw: [Inline] = tokens.map {
            switch $0 {
            case .text(let text): .text(text)
            case .tag(let raw, _): .html(raw)
            }
        }
        return clean(raw)
    }

    private enum Token {
        case text(String)
        case tag(String, HTMLTag)
    }

    /// Splits HTML into text and tags. Comments are dropped. nil if a `<` never closes.
    private static func tokenize(_ html: String) -> [Token]? {
        var tokens: [Token] = []
        var text = ""
        var i = html.startIndex
        func flushText() {
            if !text.isEmpty {
                tokens.append(.text(collapseWhitespace(HTMLEntities.decode(text))))
                text = ""
            }
        }
        while i < html.endIndex {
            if html[i...].hasPrefix("<!--") {
                flushText()
                guard let end = html.range(of: "-->", range: i..<html.endIndex) else { return nil }
                i = end.upperBound
            } else if html[i] == "<", let end = tagEnd(html, from: i) {
                let raw = String(html[i...end])
                if let tag = HTMLTag.parse(raw) {
                    flushText()
                    tokens.append(.tag(raw, tag))
                } else {
                    text += raw
                }
                i = html.index(after: end)
            } else {
                text.append(html[i])
                i = html.index(after: i)
            }
        }
        flushText()
        return tokens
    }

    /// Index of the `>` closing the tag that starts at `start`, honouring quoted attribute values.
    private static func tagEnd(_ html: String, from start: String.Index) -> String.Index? {
        var quote: Character?
        var i = html.index(after: start)
        while i < html.endIndex {
            let c = html[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
            } else if c == "<" {
                return nil
            }
            i = html.index(after: i)
        }
        return nil
    }

    private static func alignment(of tag: HTMLTag) -> BlockAlignment? {
        switch tag.attributes["align"]?.lowercased() {
        case "center": .center
        case "right": .trailing
        case "left": .leading
        default: nil
        }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for c in text {
            if c.isWhitespace, c != "\u{00A0}" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(c)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Applies inline tags, then trims whitespace at the edges and around line breaks.
    private static func clean(_ inlines: [Inline]) -> [Inline] {
        var content = HTMLInline.transform(inlines.mergingAdjacentText())
        for index in content.indices {
            guard case .text(var s) = content[index] else { continue }
            if index == 0 || content[index - 1] == .lineBreak { s = String(s.drop { $0 == " " }) }
            if index == content.count - 1 || content[index + 1] == .lineBreak {
                while s.last == " " { s.removeLast() }
            }
            content[index] = .text(s)
        }
        content.removeAll { $0 == .text("") }
        while content.first == .lineBreak { content.removeFirst() }
        while content.last == .lineBreak { content.removeLast() }
        return content
    }
}

/// `<details><summary>…</summary>` … `</details>` spread over several HTML blocks, grouped into one block.
enum DetailsHTML {
    struct Opening {
        let summary: [Inline]
        let isOpen: Bool
        /// HTML after `</summary>` in the opening block, when the whole `<details>` fits in one block.
        let inlineBody: String?
    }

    static func isOpening(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<details")
    }

    static func isClosing(_ html: String) -> Bool {
        html.lowercased().contains("</details>")
    }

    static func parseOpening(_ html: String) -> Opening? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tagEnd = trimmed.firstIndex(of: ">"), let tag = HTMLTag.parse(trimmed[...tagEnd]), tag.name == "details" else { return nil }
        let rest = String(trimmed[trimmed.index(after: tagEnd)...])
        var summary: [Inline] = [.text("Details")]
        var body = rest
        if let open = rest.range(of: "<summary", options: .caseInsensitive),
           let openEnd = rest[open.upperBound...].firstIndex(of: ">"),
           let close = rest.range(of: "</summary>", options: .caseInsensitive, range: openEnd..<rest.endIndex) {
            let inner = String(rest[rest.index(after: openEnd)..<close.lowerBound])
            summary = HTMLBlock.inlines(fromFragment: inner)
            body = String(rest[close.upperBound...])
        }
        var inlineBody: String?
        if let end = body.range(of: "</details>", options: .caseInsensitive) {
            inlineBody = String(body[..<end.lowerBound])
        }
        return Opening(summary: summary.isEmpty ? [.text("Details")] : summary, isOpen: tag.attributes["open"] != nil, inlineBody: inlineBody)
    }
}
