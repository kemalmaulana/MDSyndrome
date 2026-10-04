/// HTML / XML / SVG / plist: tags, attribute names, attribute values, comments, entities.
struct MarkupLexer {
    let chars: [Character]

    init(code: String) { chars = Array(code) }

    func run() -> [HighlightSegment] {
        var out = SegmentBuilder()
        var i = 0
        while i < chars.count {
            if matches("<!--", at: i) {
                let end = find("-->", from: i + 4).map { $0 + 3 } ?? chars.count
                out.append(String(chars[i..<end]), .comment)
                i = end
            } else if chars[i] == "<", i + 1 < chars.count, chars[i + 1].isLetter || "/!?".contains(chars[i + 1]) {
                i = tag(from: i, into: &out)
            } else if chars[i] == "&", let end = entityEnd(from: i) {
                out.append(String(chars[i..<end]), .literal)
                i = end
            } else {
                out.append(String(chars[i]), nil)
                i += 1
            }
        }
        return out.segments
    }

    /// `<name attr="value" …>`; returns the index after the closing `>`.
    private func tag(from start: Int, into out: inout SegmentBuilder) -> Int {
        var j = start + 1
        while j < chars.count, chars[j] == "/" || chars[j] == "!" || chars[j] == "?" { j += 1 }
        while j < chars.count, chars[j].isLetter || chars[j].isNumber || "-:_.".contains(chars[j]) { j += 1 }
        out.append(String(chars[start..<j]), .tag)
        while j < chars.count {
            let c = chars[j]
            if c == ">" || (c == "/" && j + 1 < chars.count && chars[j + 1] == ">") || (c == "?" && j + 1 < chars.count && chars[j + 1] == ">") {
                let end = c == ">" ? j + 1 : j + 2
                out.append(String(chars[j..<end]), .tag)
                return end
            }
            if c == "\"" || c == "'" {
                var k = j + 1
                while k < chars.count, chars[k] != c { k += 1 }
                let end = min(k + 1, chars.count)
                out.append(String(chars[j..<end]), .string)
                j = end
            } else if c.isLetter || c == "_" || c == ":" {
                var k = j
                while k < chars.count, chars[k].isLetter || chars[k].isNumber || "-:_.".contains(chars[k]) { k += 1 }
                out.append(String(chars[j..<k]), .attribute)
                j = k
            } else {
                out.append(String(c), nil)
                j += 1
            }
        }
        return j
    }

    private func entityEnd(from start: Int) -> Int? {
        var j = start + 1
        while j < chars.count, j - start <= 10, chars[j].isLetter || chars[j].isNumber || chars[j] == "#" { j += 1 }
        return j < chars.count && chars[j] == ";" && j > start + 1 ? j + 1 : nil
    }

    private func matches(_ needle: String, at index: Int) -> Bool {
        let n = Array(needle)
        guard index + n.count <= chars.count else { return false }
        return chars[index..<(index + n.count)].elementsEqual(n)
    }

    private func find(_ needle: String, from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if matches(needle, at: j) { return j }
            j += 1
        }
        return nil
    }
}

/// Unified diffs: whole lines coloured by their first character.
enum DiffLexer {
    static func run(_ code: String) -> [HighlightSegment] {
        var out = SegmentBuilder()
        for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { out.append("\n", nil) }
            let kind: TokenKind? =
                line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") ? .meta
                : line.hasPrefix("@@") ? .meta
                : line.hasPrefix("+") ? .inserted
                : line.hasPrefix("-") ? .deleted
                : nil
            out.append(line, kind)
        }
        return out.segments
    }
}
