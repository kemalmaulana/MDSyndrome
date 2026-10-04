/// YAML front matter (`---` … `---` at the very top), shown as a key/value table instead of being
/// misread as a thematic break plus a setext heading.
public struct FrontMatterEntry: Hashable, Sendable {
    public let key: String
    /// Scalar value, or the raw continuation lines (lists, nested maps) joined with newlines.
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

enum FrontMatter {
    /// Entries and the number of source lines the block spans (delimiters included).
    /// nil unless line 1 is exactly `---` and a closing `---` or `...` line follows.
    static func extract(_ lines: [Substring]) -> (entries: [FrontMatterEntry], lineCount: Int)? {
        guard let first = lines.first, trimTrailing(first) == "---" else { return nil }
        guard let close = lines.indices.dropFirst().first(where: { trimTrailing(lines[$0]) == "---" || trimTrailing(lines[$0]) == "..." }) else { return nil }
        var entries: [(key: String, value: String)] = []
        for line in lines[1..<close] {
            let text = trimTrailing(line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if let first = text.first, !first.isWhitespace, first != "-", let colon = text.firstIndex(of: ":"),
               text[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || "_-. ".contains($0) }) {
                let key = text[..<colon].trimmingSpaces()
                let value = unquote(text[text.index(after: colon)...].trimmingSpaces())
                entries.append((String(key), value))
            } else if !entries.isEmpty {
                let addition = text.trimmingSpaces()
                entries[entries.count - 1].value += entries[entries.count - 1].value.isEmpty ? addition : "\n" + addition
            }
        }
        return (entries.map { FrontMatterEntry(key: $0.key, value: $0.value) }, close + 1)
    }

    private static func trimTrailing(_ s: Substring) -> Substring {
        var s = s
        while let last = s.last, last == " " || last == "\t" || last == "\r" { s.removeLast() }
        return s
    }

    private static func unquote(_ s: Substring) -> String {
        if s.count >= 2, let f = s.first, let l = s.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            return String(s.dropFirst().dropLast())
        }
        return String(s)
    }
}

extension StringProtocol {
    func trimmingSpaces() -> SubSequence {
        let start = firstIndex { $0 != " " && $0 != "\t" } ?? endIndex
        let end = lastIndex { $0 != " " && $0 != "\t" }.map { index(after: $0) } ?? start
        return self[start..<Swift.max(start, end)]
    }
}

/// `==marked==` text (MacDown's highlight extension), within a single text run.
enum HighlightMarks {
    static func split(_ text: String) -> [Inline] {
        guard text.contains("==") else { return [.text(text)] }
        var result: [Inline] = []
        var rest = Substring(text)
        while let open = rest.range(of: "==") {
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "=="),
                  let first = afterOpen.first, !first.isWhitespace, first != "=",
                  let last = afterOpen[..<close.lowerBound].last, !last.isWhitespace else {
                // No valid closer: keep "==" literally and continue after it.
                result.append(.text(String(rest[..<open.upperBound])))
                rest = afterOpen
                continue
            }
            if open.lowerBound > rest.startIndex { result.append(.text(String(rest[..<open.lowerBound]))) }
            result.append(.highlight([.text(String(afterOpen[..<close.lowerBound]))]))
            rest = afterOpen[close.upperBound...]
        }
        if !rest.isEmpty { result.append(.text(String(rest))) }
        return result.mergingAdjacentText()
    }
}
