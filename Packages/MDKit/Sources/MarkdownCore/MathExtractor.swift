import Foundation

public enum MathExtractor {
    /// - `$$` alone on a line opens/closes a display block; it is rewritten to a
    ///   ```` ```math ```` fence, which the parser turns into `.mathBlock`.
    /// - `$$…$$` on one line becomes display math; `$…$` becomes inline math
    ///   (Pandoc rules: no space after the opening `$`, no space before the
    ///   closing `$`, closing `$` not followed by a digit).
    /// - Fenced code blocks and backtick code spans are skipped. `\$` stays literal.
    /// - Inline math never spans lines.
    public static func protect(_ source: String, singleDollar: Bool) -> ProtectedSource {
        var spans: [ProtectedSource.Span] = []
        var out: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence: (char: Character, count: Int)? = nil
        var inMathBlock = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }

            if let open = fence {
                if closesFence(line, open) { fence = nil }
                out.append(line)
                continue
            }
            if inMathBlock {
                if isDisplayDelimiter(line) {
                    inMathBlock = false
                    out.append(line.replacingOccurrences(of: "$$", with: "```"))
                } else {
                    out.append(line)
                }
                continue
            }
            if let opened = opensFence(line) {
                fence = opened
                out.append(line)
                continue
            }
            if isDisplayDelimiter(line),
               lines[(index + 1)...].contains(where: isDisplayDelimiter) {
                inMathBlock = true
                out.append(line.replacingOccurrences(of: "$$", with: "```math"))
                continue
            }
            out.append(protectInline(line, singleDollar: singleDollar, spans: &spans))
        }
        return ProtectedSource(text: out.joined(separator: "\n"), spans: spans)
    }

    private static func isDisplayDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "$$" && leadingSpaces(line) <= 3
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func opensFence(_ line: String) -> (char: Character, count: Int)? {
        guard leadingSpaces(line) <= 3 else { return nil }
        let body = line.drop(while: { $0 == " " })
        guard let first = body.first, first == "`" || first == "~" else { return nil }
        let count = body.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        if first == "`", body.dropFirst(count).contains("`") { return nil }
        return (first, count)
    }

    private static func closesFence(_ line: String, _ open: (char: Character, count: Int)) -> Bool {
        guard leadingSpaces(line) <= 3 else { return false }
        let body = line.drop(while: { $0 == " " })
        let run = body.prefix(while: { $0 == open.char }).count
        return run >= open.count && body.dropFirst(run).allSatisfy(\.isWhitespace)
    }

    private static func protectInline(_ line: String, singleDollar: Bool, spans: inout [ProtectedSource.Span]) -> String {
        let chars = Array(line)
        guard chars.contains("$") else { return line }
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                out.append(c); out.append(chars[i + 1]); i += 2
                continue
            }
            if c == "`" {
                let run = countRun(chars, from: i, of: "`")
                if let end = findClosingBackticks(chars, from: i + run, run: run) {
                    out += String(chars[i..<(end + run)])
                    i = end + run
                } else {
                    out += String(chars[i..<(i + run)])
                    i += run
                }
                continue
            }
            if c == "$", i + 1 < chars.count, chars[i + 1] == "$",
               let end = findDisplayClose(chars, from: i + 2) {
                let latex = String(chars[(i + 2)..<end]).trimmingCharacters(in: .whitespaces)
                spans.append(.init(latex: latex, display: true, original: String(chars[i..<(end + 2)])))
                out += ProtectedSource.placeholder(spans.count - 1)
                i = end + 2
                continue
            }
            if c == "$", singleDollar, let end = findInlineClose(chars, from: i) {
                spans.append(.init(latex: String(chars[(i + 1)..<end]), display: false, original: String(chars[i...end])))
                out += ProtectedSource.placeholder(spans.count - 1)
                i = end + 1
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func countRun(_ chars: [Character], from start: Int, of char: Character) -> Int {
        var n = 0
        while start + n < chars.count, chars[start + n] == char { n += 1 }
        return n
    }

    private static func findClosingBackticks(_ chars: [Character], from start: Int, run: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                let n = countRun(chars, from: j, of: "`")
                if n == run { return j }
                j += n
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func findDisplayClose(_ chars: [Character], from start: Int) -> Int? {
        var j = start
        while j + 1 < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$", chars[j + 1] == "$" { return j > start ? j : nil }
            j += 1
        }
        return nil
    }

    private static func findInlineClose(_ chars: [Character], from open: Int) -> Int? {
        let first = open + 1
        guard first < chars.count, !chars[first].isWhitespace, chars[first] != "$" else { return nil }
        var j = first
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$" {
                let before = chars[j - 1]
                let after: Character? = j + 1 < chars.count ? chars[j + 1] : nil
                if j > first, !before.isWhitespace, !(after?.isNumber ?? false) { return j }
            }
            j += 1
        }
        return nil
    }
}
