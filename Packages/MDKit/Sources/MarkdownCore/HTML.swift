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
    ///
    /// Linear: every tag is parsed once and pairs are found with one stack pass (nearest open tag of the
    /// same name, like browsers). Nesting deeper than `NodeConverter.maxDepth` is left as raw HTML so
    /// hostile input like 2,000 nested `<b>` can't overflow the parse thread's stack.
    static func transform(_ inlines: [Inline]) -> [Inline] {
        guard inlines.contains(where: { if case .html = $0 { true } else { false } }) else { return inlines }
        let tags: [HTMLTag?] = inlines.map { if case .html(let raw) = $0 { HTMLTag.parse(raw) } else { nil } }
        let closeOf = pairs(tags)
        return build(inlines, tags: tags, closeOf: closeOf, range: 0..<inlines.count, depth: 0).mergingAdjacentText()
    }

    /// closeOf[i] = index of the tag closing the wrapper opened at i.
    private static func pairs(_ tags: [HTMLTag?]) -> [Int: Int] {
        var closeOf: [Int: Int] = [:]
        var stack: [(name: String, index: Int)] = []
        var openCount: [String: Int] = [:]
        for (index, tag) in tags.enumerated() {
            guard let tag, !tag.isSelfClosing, wrappers.contains(tag.name) else { continue }
            if !tag.isClosing {
                stack.append((tag.name, index))
                openCount[tag.name, default: 0] += 1
                continue
            }
            // Closing tag: match the nearest open tag of the same name. Tags opened after it stay unmatched.
            guard openCount[tag.name, default: 0] > 0 else { continue }
            while let top = stack.popLast() {
                openCount[top.name, default: 0] -= 1
                if top.name == tag.name {
                    closeOf[top.index] = index
                    break
                }
            }
        }
        return closeOf
    }

    private static func build(_ inlines: [Inline], tags: [HTMLTag?], closeOf: [Int: Int], range: Range<Int>, depth: Int) -> [Inline] {
        var result: [Inline] = []
        var i = range.lowerBound
        while i < range.upperBound {
            guard let tag = tags[i], !tag.isClosing else {
                result.append(inlines[i])
                i += 1
                continue
            }
            if tag.isSelfClosing {
                switch tag.name {
                case "br": result.append(.lineBreak)
                case "img": result.append(image(from: tag))
                case "source": break   // <picture> sources: the <img> fallback is used
                default: result.append(inlines[i])
                }
                i += 1
                continue
            }
            if let close = closeOf[i], close < range.upperBound, depth < NodeConverter.maxDepth {
                let children = build(inlines, tags: tags, closeOf: closeOf, range: (i + 1)..<close, depth: depth + 1)
                result.append(contentsOf: wrap(children, in: tag))
                i = close + 1
            } else {
                result.append(inlines[i])
                i += 1
            }
        }
        return result
    }

    private static func image(from tag: HTMLTag) -> Inline {
        let width = tag.attributes["width"].flatMap { Double($0.replacingOccurrences(of: "px", with: "")) }
        return .image(source: tag.attributes["src"] ?? "", title: tag.attributes["title"], alt: tag.attributes["alt"] ?? "", width: width)
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
    /// A `<` always ends the search (even inside an unclosed quote), so every scan stops at the next
    /// tag and tokenizing stays linear on malformed input like thousands of `<a title='x>`.
    private static func tagEnd(_ html: String, from start: String.Index) -> String.Index? {
        var quote: Character?
        var i = html.index(after: start)
        while i < html.endIndex {
            let c = html[i]
            if c == "<" { return nil }
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
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

/// `<details><summary>…</summary>` … `</details>`, possibly spread over several HTML blocks with
/// Markdown between them, grouped into one collapsible block.
enum DetailsHTML {
    enum Segment: Equatable {
        /// From `<details …>` up to the next details tag: the tag, the `<summary>` and any HTML body.
        case opening(String)
        case closing
        case other(String)
    }

    struct Opening {
        let summary: [Inline]
        let isOpen: Bool
        /// HTML after `</summary>` (or after the `<details>` tag when there is no summary).
        let body: String
    }

    /// Splits raw HTML at every `<details …>` and `</details>` tag, so content sharing a block with
    /// them is never lost. nil when the HTML has no details tags at all.
    static func segments(_ html: String) -> [Segment]? {
        let lower = html.lowercased()
        guard lower.contains("<details") || lower.contains("</details>") else { return nil }
        var markers: [(range: Range<String.Index>, isClosing: Bool)] = []
        var searchStart = lower.startIndex
        while let open = lower.range(of: "<details", range: searchStart..<lower.endIndex) {
            let next = open.upperBound < lower.endIndex ? lower[open.upperBound] : ">"
            if next.isWhitespace || next == ">" || next == "/" { markers.append((open, false)) }
            searchStart = open.upperBound
        }
        searchStart = lower.startIndex
        while let close = lower.range(of: "</details>", range: searchStart..<lower.endIndex) {
            markers.append((close, true))
            searchStart = close.upperBound
        }
        guard !markers.isEmpty else { return nil }
        markers.sort { $0.range.lowerBound < $1.range.lowerBound }

        // `lower` and `html` share indices: lowercasing ASCII tag names doesn't change lengths here,
        // but to be safe slice `html` through utf16 offsets.
        func slice(_ from: String.Index, _ to: String.Index) -> String {
            let a = lower.utf16.distance(from: lower.startIndex, to: from)
            let b = lower.utf16.distance(from: lower.startIndex, to: to)
            let start = html.utf16.index(html.startIndex, offsetBy: a)
            let end = html.utf16.index(html.startIndex, offsetBy: b)
            return String(html[start..<end])
        }

        var segments: [Segment] = []
        var cursor = lower.startIndex
        for (index, marker) in markers.enumerated() {
            let before = slice(cursor, marker.range.lowerBound)
            if !before.allSatisfy(\.isWhitespace) { segments.append(.other(before)) }
            if marker.isClosing {
                segments.append(.closing)
                cursor = marker.range.upperBound
            } else {
                let end = index + 1 < markers.count ? markers[index + 1].range.lowerBound : lower.endIndex
                segments.append(.opening(slice(marker.range.lowerBound, end).trimmingCharacters(in: .whitespacesAndNewlines)))
                cursor = end
            }
        }
        let tail = slice(cursor, lower.endIndex)
        if !tail.allSatisfy(\.isWhitespace) { segments.append(.other(tail)) }
        return segments
    }

    static func isOpeningMarker(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("<details") else { return false }
        let next = trimmed.dropFirst("<details".count).first ?? ">"
        return next.isWhitespace || next == ">" || next == "/"
    }

    static func isClosingMarker(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "</details>"
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
            let parsed = HTMLBlock.inlines(fromFragment: inner)
            if !parsed.isEmpty { summary = parsed }
            body = String(rest[close.upperBound...])
        }
        return Opening(summary: summary, isOpen: tag.attributes["open"] != nil, body: body)
    }
}
