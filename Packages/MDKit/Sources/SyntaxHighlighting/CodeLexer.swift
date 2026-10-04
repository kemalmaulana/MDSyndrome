/// Single-pass, table-driven tokenizer. Linear in the input; never backtracks more than a few characters.
struct CodeLexer {
    let definition: LanguageDefinition
    let chars: [Character]
    private let delimiters: [[Character]]
    private let lineComments: [[Character]]
    private let blockComments: [(open: [Character], close: [Character])]

    init(definition: LanguageDefinition, code: String) {
        self.definition = definition
        self.chars = Array(code)
        self.delimiters = definition.stringDelimiters.map(Array.init).sorted { $0.count > $1.count }
        self.lineComments = definition.lineComments.map(Array.init)
        self.blockComments = definition.blockComments.map { (Array($0.open), Array($0.close)) }
    }

    func run() -> [HighlightSegment] {
        var out = SegmentBuilder()
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if let (open, close) = blockComments.first(where: { matches($0.open, at: i) }) {
                let end = find(close, from: i + open.count).map { $0 + close.count } ?? chars.count
                out.append(String(chars[i..<end]), .comment)
                i = end
                continue
            }
            if lineComments.contains(where: { matches($0, at: i) }) {
                let end = lineEnd(from: i)
                out.append(String(chars[i..<end]), .comment)
                i = end
                continue
            }
            if let delimiter = delimiters.first(where: { matches($0, at: i) }) {
                if delimiter == ["'"], definition.singleQuoteIsChar {
                    if let end = charLiteralEnd(from: i) {
                        out.append(String(chars[i..<end]), .string)
                        i = end
                    } else {
                        out.append(String(c), nil)
                        i += 1
                    }
                    continue
                }
                let end = stringEnd(from: i, delimiter: delimiter)
                let kind: TokenKind = definition.keysBeforeColon && followedByColon(end) ? .attribute : .string
                out.append(String(chars[i..<end]), kind)
                i = end
                continue
            }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber && !(i > 0 && isIdentifierChar(chars[i - 1]))) {
                let end = numberEnd(from: i)
                out.append(String(chars[i..<end]), .number)
                i = end
                continue
            }
            if definition.attributePrefixes.contains(c), i + 1 < chars.count, isIdentifierStart(chars[i + 1]) || chars[i + 1] == "[" {
                let end = identifierEnd(from: i + 1)
                out.append(String(chars[i..<end]), .attribute)
                i = end
                continue
            }
            if let prefix = definition.variablePrefix, c == prefix, i + 1 < chars.count, isIdentifierStart(chars[i + 1]) || chars[i + 1] == "{" {
                let end = chars[i + 1] == "{" ? (find(["}"], from: i + 2).map { $0 + 1 } ?? i + 2) : identifierEnd(from: i + 1)
                out.append(String(chars[i..<end]), .attribute)
                i = end
                continue
            }
            if isIdentifierStart(c) {
                let end = identifierEnd(from: i)
                let word = String(chars[i..<end])
                out.append(word, classify(word, end: end))
                i = end
                continue
            }
            out.append(String(c), nil)
            i += 1
        }
        return out.segments
    }

    // MARK: - Classification

    private func classify(_ word: String, end: Int) -> TokenKind? {
        let key = definition.caseInsensitiveKeywords ? word.lowercased() : word
        if definition.keysBeforeColon, followedByColon(end) { return .attribute }
        if definition.keywords.contains(key) { return .keyword }
        if definition.literals.contains(key) { return .literal }
        if definition.types.contains(key) { return .type }
        if definition.capitalizedIsType, let first = word.first, first.isUppercase { return .type }
        return nil
    }

    private func followedByColon(_ index: Int) -> Bool {
        var j = index
        while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
        guard j < chars.count, chars[j] == ":" else { return false }
        return !(j + 1 < chars.count && chars[j + 1] == ":")   // `::` is a path separator, not a key
    }

    // MARK: - Scanning

    private func isIdentifierStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || definition.identifierExtras.contains(c) && c != "-"
    }

    private func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || definition.identifierExtras.contains(c)
    }

    private func identifierEnd(from start: Int) -> Int {
        var j = start
        while j < chars.count, isIdentifierChar(chars[j]) { j += 1 }
        return max(j, start + 1)
    }

    private func numberEnd(from start: Int) -> Int {
        let isHex = start + 1 < chars.count && chars[start] == "0" && (chars[start + 1] == "x" || chars[start + 1] == "X")
        var j = start
        while j < chars.count {
            let c = chars[j]
            if c == ".", j + 1 < chars.count, chars[j + 1] == "." { break }   // range operators: 1..<5, 0...9
            guard c.isNumber || c.isLetter || c == "_" || c == "." else { break }
            j += 1
            // exponent sign: 1e-9, 2.5E+3 (not in hex, where e/E are digits)
            if !isHex, c == "e" || c == "E", j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
        }
        return j
    }

    private func stringEnd(from start: Int, delimiter: [Character]) -> Int {
        let multiline = delimiter.count > 1 || delimiter == ["`"]
        var j = start + delimiter.count
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if matches(delimiter, at: j) { return j + delimiter.count }
            if !multiline, chars[j] == "\n" { return j }
            j += 1
        }
        return chars.count
    }

    /// `'x'` or an escape like `'\n'` / `'\u{1F600}'`. Anything else (Rust lifetimes `'a`) is not a literal.
    private func charLiteralEnd(from start: Int) -> Int? {
        guard start + 2 < chars.count else { return nil }
        if chars[start + 1] == "\\" {
            var j = start + 2
            let limit = min(chars.count, start + 14)
            while j < limit, chars[j] != "\n" {
                if chars[j] == "'", j > start + 2 { return j + 1 }
                j += 1
            }
            return nil
        }
        let content = chars[start + 1]
        return content != "'" && content != "\n" && chars[start + 2] == "'" ? start + 3 : nil
    }

    private func lineEnd(from start: Int) -> Int {
        var j = start
        while j < chars.count, chars[j] != "\n" { j += 1 }
        return j
    }

    private func matches(_ needle: [Character], at index: Int) -> Bool {
        guard index + needle.count <= chars.count else { return false }
        for (offset, c) in needle.enumerated() where chars[index + offset] != c { return false }
        return true
    }

    private func find(_ needle: [Character], from start: Int) -> Int? {
        var j = start
        while j + needle.count <= chars.count {
            if matches(needle, at: j) { return j }
            j += 1
        }
        return nil
    }
}
