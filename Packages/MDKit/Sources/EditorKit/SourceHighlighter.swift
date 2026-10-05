import Foundation

/// What a run of Markdown source is, for colouring in the editor (MacDown's style vocabulary).
public enum EditorTokenKind: String, Hashable, Sendable, CaseIterable, Codable {
    case heading1, heading2, heading3, heading4, heading5, heading6
    case emphasis, strong, strikethrough, highlight
    case code, codeBlock, math, frontMatter
    case link, url, image, reference
    case listMarker, taskMarker, blockquote, horizontalRule
    case html, htmlEntity, comment
}

/// A token in one line; `range` is UTF-16 and relative to the line start.
public struct SourceToken: Hashable, Sendable {
    public let range: NSRange
    public let kind: EditorTokenKind

    public init(range: NSRange, kind: EditorTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Multi-line context carried from one line to the next.
public enum LineState: Hashable, Sendable {
    /// The state of the document's first line, the only place front matter can open.
    case documentStart
    case normal
    /// Line 1 was `---`; the next line decides whether this is YAML front matter or a thematic break.
    case frontMatterCandidate
    /// Inside YAML front matter, up to the closing `---` or `...`.
    case frontMatter
    /// Inside a fenced code block opened with `count` × `fence` (` or ~).
    case fence(Character, Int)
    /// Inside a `$$` display-math block.
    case math
    /// Inside an unterminated `<!-- … -->` comment.
    case comment
}

/// Line-at-a-time Markdown tokenizer for editor colouring. Each line costs a few regex passes at
/// most (usually none: the first character rules most patterns out), and only lines near an edit
/// are re-run (see EditorHighlighter), so typing stays cheap in big files.
public enum SourceHighlighter {
    /// Lines longer than this (UTF-16 units) get block-level colouring only. Inline patterns are
    /// not worth their cost on a minified one-line file, and it bounds the worst case.
    public static let maxInlineLength = 4000

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    private static let fenceOpen = regex(#"^ {0,3}(`{3,}|~{3,})"#)
    private static let heading = regex(#"^ {0,3}(#{1,6})(?:[ \t]|$)"#)
    private static let rule = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let quote = regex(#"^ {0,3}>"#)
    private static let listMarker = regex(#"^[ \t]*([-*+]|\d{1,9}[.)])(?=[ \t]|$)"#)
    private static let task = regex(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])"#)
    private static let referenceDefinition = regex(#"^ {0,3}(\[\^?[^\]]+\]):[ \t]*(\S*)"#)
    private static let frontMatterKey = regex(#"^[A-Za-z0-9_][A-Za-z0-9_\-. ]*:"#)

    private static let codeSpan = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let displayMath = regex(#"\$\$[^$]+\$\$"#)
    private static let inlineMath = regex(#"(?<![\\$])\$(?=[^\s$])[^$]*?(?<=[^\s\\$])\$(?!\d)"#)
    private static let image = regex(#"!\[[^\]]*\]\([^)]*\)"#)
    private static let inlineLink = regex(#"(\[[^\]]+\])(\([^)\s]*(?:[ \t]+"[^"]*")?\))"#)
    private static let referenceLink = regex(#"\[[^\]]+\]\[[^\]]*\]"#)
    private static let footnote = regex(#"\[\^[^\]]+\]"#)
    private static let autolink = regex(#"<(?:https?|mailto):[^>\s]+>|https?://[^\s<>()\[\]]+"#)
    private static let strong = regex(#"(?<!\\)(\*\*|__)(?=\S)(.+?)(?<=[^\s\\])\1"#)
    private static let emphasisStar = regex(#"(?<![*\w\\])\*(?=[^\s*])(.+?)(?<=[^\s*\\])\*(?![*\w])"#)
    private static let emphasisUnderscore = regex(#"(?<![\w_\\])_(?=[^\s_])(.+?)(?<=[^\s_\\])_(?![\w_])"#)
    private static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let highlight = regex(#"==(?=\S)(.+?)(?<=\S)=="#)
    private static let htmlComment = regex(#"<!--.*?-->"#)
    private static let htmlTag = regex(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#)
    private static let entity = regex(#"&(?:#\d+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);"#)

    private static let headingKinds: [EditorTokenKind] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]

    /// Tokens for one line (without its line terminator) and the state at the start of the next line.
    public static func tokens(line: String, state: LineState) -> (tokens: [SourceToken], next: LineState) {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)

        switch state {
        case .fence(let char, let count):
            let trimmed = trimmedSpaces(line)
            let run = trimmed.prefix { $0 == char }.count
            let closes = run >= count && trimmed.dropFirst(run).allSatisfy(\.isWhitespace) && line.prefix { $0 == " " }.count <= 3
            return ([SourceToken(range: all, kind: .codeBlock)], closes ? .normal : state)
        case .math:
            return ([SourceToken(range: all, kind: .math)], trimmedSpaces(line) == "$$" ? .normal : .math)
        case .comment:
            let end = ns.range(of: "-->")
            guard end.location != NSNotFound else { return ([SourceToken(range: all, kind: .comment)], .comment) }
            let commentEnd = NSMaxRange(end)
            var tokens = [SourceToken(range: NSRange(location: 0, length: commentEnd), kind: .comment)]
            tokens += inlineTokens(ns, in: NSRange(location: commentEnd, length: ns.length - commentEnd))
            return (tokens, .normal)
        case .frontMatter:
            let trimmed = trimmedSpaces(line)
            let closes = trimmed == "---" || trimmed == "..."
            return ([SourceToken(range: all, kind: closes ? .horizontalRule : .frontMatter)], closes ? .normal : .frontMatter)
        case .frontMatterCandidate:
            if frontMatterKey.firstMatch(in: line, options: .anchored, range: all) != nil {
                return ([SourceToken(range: all, kind: .frontMatter)], .frontMatter)
            }
            // Not `key:` → the opening `---` was an ordinary thematic break. Colour this line normally.
        case .documentStart:
            if trimmedSpaces(line) == "---" { return ([SourceToken(range: all, kind: .horizontalRule)], .frontMatterCandidate) }
        case .normal:
            break
        }

        // Block-level syntax is decided by the first non-blank character, so most lines skip every regex here.
        var indent = 0
        var first: unichar = 0
        while indent < ns.length {
            let unit = ns.character(at: indent)
            if unit == 0x20 || unit == 0x09 { indent += 1 } else { first = unit; break }
        }
        let shallow = indent <= 3   // 4+ columns of indent can't open a fence, heading, rule, quote or definition

        if shallow, first == 0x60 || first == 0x7E,   // ` ~
           let match = fenceOpen.firstMatch(in: line, options: .anchored, range: all) {
            let fence = ns.substring(with: match.range(at: 1))
            let info = ns.substring(from: NSMaxRange(match.range))
            if fence.first != "`" || !info.contains("`") {
                return ([SourceToken(range: all, kind: .codeBlock)], .fence(fence.first!, fence.count))
            }
        }
        if first == 0x24, trimmedSpaces(line) == "$$" { return ([SourceToken(range: all, kind: .math)], .math) }   // $

        var tokens: [SourceToken] = []
        if shallow, first == 0x23, let match = heading.firstMatch(in: line, options: .anchored, range: all) {   // #
            tokens.append(SourceToken(range: all, kind: headingKinds[match.range(at: 1).length - 1]))
        } else if shallow, first == 0x2D || first == 0x2A || first == 0x5F, rule.firstMatch(in: line, options: .anchored, range: all) != nil {   // - * _
            return ([SourceToken(range: all, kind: .horizontalRule)], .normal)
        } else if shallow, first == 0x5B, let match = referenceDefinition.firstMatch(in: line, options: .anchored, range: all) {   // [
            tokens.append(SourceToken(range: match.range(at: 1), kind: .reference))
            if match.range(at: 2).length > 0 { tokens.append(SourceToken(range: match.range(at: 2), kind: .url)) }
            return (tokens, .normal)
        } else {
            if shallow, first == 0x3E { tokens.append(SourceToken(range: all, kind: .blockquote)) }   // >
            if first == 0x2D || first == 0x2A || first == 0x2B || (first >= 0x30 && first <= 0x39),
               let match = listMarker.firstMatch(in: line, options: .anchored, range: all) {
                tokens.append(SourceToken(range: match.range(at: 1), kind: .listMarker))
                if let taskMatch = task.firstMatch(in: line, options: .anchored, range: all) {
                    tokens.append(SourceToken(range: taskMatch.range(at: 1), kind: .taskMarker))
                }
            }
        }

        guard ns.length <= maxInlineLength else { return (tokens, .normal) }

        // An unterminated <!-- swallows the rest of the line and carries over.
        let open = ns.range(of: "<!--")
        if open.location != NSNotFound, ns.range(of: "-->", range: NSRange(location: open.location, length: ns.length - open.location)).location == NSNotFound {
            tokens += inlineTokens(ns, in: NSRange(location: 0, length: open.location))
            tokens.append(SourceToken(range: NSRange(location: open.location, length: ns.length - open.location), kind: .comment))
            return (tokens, .comment)
        }
        tokens += inlineTokens(ns, in: all)
        return (tokens, .normal)
    }

    private static func trimmedSpaces(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    /// Inline tokens in `range`. Code spans and math are found first; nothing else is coloured inside them.
    private static func inlineTokens(_ ns: NSString, in range: NSRange) -> [SourceToken] {
        guard range.length > 0, ns.length <= maxInlineLength else { return [] }
        let line = ns as String
        var tokens: [SourceToken] = []
        var protected: [NSRange] = []

        func add(_ expression: NSRegularExpression, _ kind: EditorTokenKind, group: Int = 0, protect: Bool = false) {
            expression.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let r = match?.range(at: group), r.location != NSNotFound,
                      !protected.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { return }
                tokens.append(SourceToken(range: r, kind: kind))
                if protect { protected.append(match!.range) }
            }
        }
        func has(_ needle: String) -> Bool { ns.range(of: needle, range: range).location != NSNotFound }

        if has("`") { add(codeSpan, .code, protect: true) }
        if has("$") {
            add(displayMath, .math, protect: true)
            add(inlineMath, .math, protect: true)
        }
        if has("<!--") { add(htmlComment, .comment, protect: true) }
        if has("](") || has("][") || has("[^") {
            add(image, .image, protect: true)
            add(inlineLink, .link, group: 1)
            add(inlineLink, .url, group: 2)
            add(referenceLink, .link)
            add(footnote, .reference)
        }
        if has("http") || has("mailto:") { add(autolink, .url) }
        if has("<") { add(htmlTag, .html) }
        if has("&") { add(entity, .htmlEntity) }
        if has("**") || has("__") { add(strong, .strong) }
        if has("*") { add(emphasisStar, .emphasis) }
        if has("_") { add(emphasisUnderscore, .emphasis) }
        if has("~~") { add(strikethrough, .strikethrough) }
        if has("==") { add(highlight, .highlight) }
        return tokens
    }
}
