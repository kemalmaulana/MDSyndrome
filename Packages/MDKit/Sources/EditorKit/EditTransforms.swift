import Foundation

/// One replacement in the editor's text, plus where the selection goes afterwards.
/// Ranges are UTF-16 (`NSRange`), the units NSTextView uses.
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The text after applying the edit (used by tests and by callers that need the result).
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Line prefixes the format commands toggle.
public enum LinePrefix: Sendable {
    case blockquote, bullet, numbered, task
}

/// Pure Markdown editing operations. Each returns the edit to apply, or nil to let the text view
/// do its default thing.
public enum EditTransforms {
    // MARK: Return: continue lists and quotes (ED-5)

    private static let listItem = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"^([ \t]*>[ \t]?)+"#)

    /// Return pressed. Continues a list item (next bullet / number / unchecked task) or a quote;
    /// on an empty item, removes the marker instead (ends the list). nil → plain newline.
    public static func newline(in text: NSString, selection: NSRange, renumber: Bool = true) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let cursor = selection.location
        let line = text.lineRange(for: NSRange(location: cursor, length: 0))
        let lineStart = line.location
        let lineEnd = lineContentEnd(text, line)
        let head = text.substring(with: NSRange(location: lineStart, length: cursor - lineStart))

        if let match = listItem.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) {
            let ns = head as NSString
            let indent = ns.substring(with: match.range(at: 1))
            let marker = ns.substring(with: match.range(at: 2))
            let gap = ns.substring(with: match.range(at: 3))
            let isTask = match.range(at: 4).location != NSNotFound
            let rest = text.substring(with: NSRange(location: lineStart + match.range.length, length: max(0, lineEnd - lineStart - match.range.length)))
            if rest.trimmingCharacters(in: .whitespaces).isEmpty, cursor >= lineStart + match.range.length {
                // Empty item: Return ends the list by removing the marker.
                return TextEdit(range: NSRange(location: lineStart, length: lineEnd - lineStart), replacement: "", selection: NSRange(location: lineStart, length: 0))
            }
            var nextMarker = marker
            if let number = Int(marker.dropLast()) {
                nextMarker = "\(number + 1)\(marker.last!)"
            }
            let insertion = "\n" + indent + nextMarker + gap + (isTask ? "[ ] " : "")
            var edit = TextEdit(range: NSRange(location: cursor, length: 0), replacement: insertion,
                                selection: NSRange(location: cursor + (insertion as NSString).length, length: 0))
            if renumber, let number = Int(marker.dropLast()) {
                edit = renumbered(edit, in: text, after: line, indent: indent, delimiter: marker.last!, from: number + 2)
            }
            return edit
        }

        if let match = quotePrefix.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) {
            let prefix = (head as NSString).substring(with: match.range)
            let rest = text.substring(with: NSRange(location: lineStart + match.range.length, length: max(0, lineEnd - lineStart - match.range.length)))
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return TextEdit(range: NSRange(location: lineStart, length: lineEnd - lineStart), replacement: "", selection: NSRange(location: lineStart, length: 0))
            }
            let insertion = "\n" + prefix
            return TextEdit(range: NSRange(location: cursor, length: 0), replacement: insertion,
                            selection: NSRange(location: cursor + (insertion as NSString).length, length: 0))
        }
        return nil
    }

    /// Extends `edit` so following ordered items at the same indent continue the sequence.
    private static func renumbered(_ edit: TextEdit, in text: NSString, after line: NSRange, indent: String, delimiter: Character, from first: Int) -> TextEdit {
        let pattern = try! NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: indent) + #"(\d{1,9})"# + NSRegularExpression.escapedPattern(for: String(delimiter)) + #"[ \t]"#)
        var next = first
        var position = NSMaxRange(line)
        var rewritten = ""
        while position < text.length {
            let following = text.lineRange(for: NSRange(location: position, length: 0))
            let content = text.substring(with: following)
            guard let match = pattern.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { break }
            let numberRange = match.range(at: 1)
            rewritten += (content as NSString).replacingCharacters(in: numberRange, with: "\(next)")
            next += 1
            position = NSMaxRange(following)
        }
        guard !rewritten.isEmpty else { return edit }
        // One edit from the cursor to the end of the renumbered lines.
        let tailStart = edit.range.location
        let between = text.substring(with: NSRange(location: tailStart, length: NSMaxRange(line) - tailStart))
        return TextEdit(
            range: NSRange(location: tailStart, length: position - tailStart),
            replacement: edit.replacement + between + rewritten,
            selection: edit.selection
        )
    }

    // MARK: Tab / Shift-Tab (ED-6)

    /// Indents every line the selection touches by `unit`. With an empty selection on a line that
    /// is not a list item, inserts `unit` at the cursor instead (like a normal Tab), unless
    /// `wholeLines` asks for the line to be indented (the Indent menu command).
    public static func indent(in text: NSString, selection: NSRange, unit: String, wholeLines: Bool = false) -> TextEdit {
        let lines = text.lineRange(for: selection)
        let firstLine = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let isListLine = listItem.firstMatch(in: text.substring(with: firstLine), range: NSRange(location: 0, length: firstLine.length)) != nil
        if selection.length == 0, !isListLine, !wholeLines {
            return TextEdit(range: selection, replacement: unit, selection: NSRange(location: selection.location + (unit as NSString).length, length: 0))
        }
        let original = text.substring(with: lines)
        let indented = mapLines(original) { line in
            line.isEmpty && selection.length > 0 ? line : unit + line
        }
        let unitLength = (unit as NSString).length
        let newSelection = selection.length == 0
            ? NSRange(location: selection.location + unitLength, length: 0)
            : NSRange(location: lines.location, length: (indented as NSString).length - (hasTrailingNewline(original) ? 1 : 0))
        return TextEdit(range: lines, replacement: indented, selection: newSelection)
    }

    /// Removes up to one `unit` (or one tab) of leading whitespace from every line the selection touches.
    public static func outdent(in text: NSString, selection: NSRange, unit: String) -> TextEdit? {
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        let width = (unit as NSString).length
        var removedOnFirst = 0
        var first = true
        let outdented = mapLines(original) { line in
            var removed = 0
            var result = Substring(line)
            if result.hasPrefix("\t") {
                result = result.dropFirst()
                removed = 1
            } else {
                while removed < width, result.hasPrefix(" ") {
                    result = result.dropFirst()
                    removed += 1
                }
            }
            if first { removedOnFirst = removed; first = false }
            return String(result)
        }
        guard outdented != original else { return nil }
        let newSelection = selection.length == 0
            ? NSRange(location: max(lines.location, selection.location - removedOnFirst), length: 0)
            : NSRange(location: lines.location, length: (outdented as NSString).length - (hasTrailingNewline(original) ? 1 : 0))
        return TextEdit(range: lines, replacement: outdented, selection: newSelection)
    }

    // MARK: Auto-pairing (ED-7)

    static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    static let closers: Set<String> = [")", "]", "}", "\"", "'", "`"]

    /// A character was typed. Wraps a selection in the pair, types over an existing closer, or inserts
    /// the closing character after the cursor. nil → insert the character normally.
    public static func typed(_ character: String, in text: NSString, selection: NSRange) -> TextEdit? {
        let next = selection.location + selection.length < text.length ? text.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) : ""
        let previous = selection.location > 0 ? text.substring(with: NSRange(location: selection.location - 1, length: 1)) : ""

        if selection.length > 0, let close = pairs[character] {
            let inner = text.substring(with: selection)
            return TextEdit(range: selection, replacement: character + inner + close,
                            selection: NSRange(location: selection.location + 1, length: selection.length))
        }
        guard selection.length == 0 else { return nil }
        if closers.contains(character), next == character {
            // Type over the closer we inserted earlier.
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        guard let close = pairs[character] else { return nil }
        let isQuote = character == close
        if isQuote, previous.first.map({ $0.isLetter || $0.isNumber }) == true { return nil }   // don't, it's
        if let n = next.first, n.isLetter || n.isNumber { return nil }                            // before a word
        return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: character + close,
                        selection: NSRange(location: selection.location + 1, length: 0))
    }

    /// Backspace between an empty pair (`(|)`) deletes both. nil → normal backspace.
    public static func deleteBackward(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location > 0, selection.location < text.length else { return nil }
        let previous = text.substring(with: NSRange(location: selection.location - 1, length: 1))
        let next = text.substring(with: NSRange(location: selection.location, length: 1))
        guard pairs[previous] == next else { return nil }
        return TextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "",
                        selection: NSRange(location: selection.location - 1, length: 0))
    }

    // MARK: Format commands (ED-8)

    /// Wraps the selection (or the word at the cursor) in `marker`, or unwraps it when already wrapped.
    /// With nothing to wrap, inserts an empty pair with the cursor between.
    public static func toggleWrap(_ marker: String, in text: NSString, selection: NSRange) -> TextEdit {
        if marker == "*" || marker == "**", let edit = toggleStars(marker.count, in: text, selection: selection) { return edit }
        return toggleLiteralWrap(marker, in: text, selection: selection)
    }

    /// Italic (`*`) and bold (`**`) share a character, so they are decided by the run of stars around
    /// the text: 1 is italic, 2 is bold, 3 is both. Toggling one leaves the other alone
    /// (`**word**` + italic → `***word***`; `***word***` + bold → `*word*`).
    private static func toggleStars(_ count: Int, in text: NSString, selection: NSRange) -> TextEdit? {
        var target = selection
        if target.length == 0 { target = word(in: text, at: selection.location) ?? target }
        func isStar(_ i: Int) -> Bool { i >= 0 && i < text.length && text.character(at: i) == 0x2A }

        var start = target.location
        var end = NSMaxRange(target)
        while start < end, isStar(start) { start += 1 }     // stars the selection already includes
        while end > start, isStar(end - 1) { end -= 1 }
        var runStart = start
        while isStar(runStart - 1) { runStart -= 1 }
        var runEnd = end
        while isStar(runEnd) { runEnd += 1 }

        let leading = start - runStart
        let trailing = runEnd - end
        let paired = Swift.min(leading, trailing)
        let active = count == 1 ? (paired == 1 || paired == 3) : paired >= 2
        if start == end, !active { return nil }   // nothing to wrap: caller inserts a fresh pair
        let change = active ? -count : count
        let inner = text.substring(with: NSRange(location: start, length: end - start))
        let replacement = String(repeating: "*", count: leading + change) + inner + String(repeating: "*", count: trailing + change)
        return TextEdit(range: NSRange(location: runStart, length: runEnd - runStart), replacement: replacement,
                        selection: NSRange(location: runStart + leading + change, length: (inner as NSString).length))
    }

    private static func toggleLiteralWrap(_ marker: String, in text: NSString, selection: NSRange) -> TextEdit {
        let m = (marker as NSString).length
        var target = selection
        if target.length == 0 { target = word(in: text, at: selection.location) ?? target }

        // Already wrapped outside the target: **word** with `word` selected.
        if target.location >= m, NSMaxRange(target) + m <= text.length,
           text.substring(with: NSRange(location: target.location - m, length: m)) == marker,
           text.substring(with: NSRange(location: NSMaxRange(target), length: m)) == marker {
            let inner = text.substring(with: target)
            return TextEdit(range: NSRange(location: target.location - m, length: target.length + 2 * m), replacement: inner,
                            selection: NSRange(location: target.location - m, length: target.length))
        }
        // Already wrapped inside the target: `**word**` selected.
        let selected = text.substring(with: target)
        if target.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return TextEdit(range: target, replacement: inner, selection: NSRange(location: target.location, length: (inner as NSString).length))
        }
        if target.length == 0 {
            return TextEdit(range: target, replacement: marker + marker, selection: NSRange(location: target.location + m, length: 0))
        }
        return TextEdit(range: target, replacement: marker + selected + marker, selection: NSRange(location: target.location + m, length: target.length))
    }

    /// `[selection](url)` with "url" selected, or `![…](url)` for images.
    public static func insertLink(image: Bool, in text: NSString, selection: NSRange) -> TextEdit {
        let label = text.substring(with: selection)
        let bang = image ? "!" : ""
        if label.hasPrefix("http://") || label.hasPrefix("https://") {
            let replacement = "\(bang)[](\(label))"
            return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + bang.count + 1, length: 0))
        }
        let replacement = "\(bang)[\(label)](url)"
        let urlStart = selection.location + (bang as NSString).length + 1 + (label as NSString).length + 2
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: urlStart, length: 3))
    }

    /// Sets every touched line to heading `level` (1…6); the same level again removes the heading.
    public static func setHeading(level: Int, in text: NSString, selection: NSRange) -> TextEdit {
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        let marks = String(repeating: "#", count: max(1, min(6, level))) + " "
        let headingPrefix = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}[ \t]*"#)
        let allAtLevel = original.split(separator: "\n", omittingEmptySubsequences: true).allSatisfy { $0.hasPrefix(marks) }
        let updated = mapLines(original) { line in
            guard !line.isEmpty else { return line }
            let ns = line as NSString
            let stripped = headingPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)).map { ns.substring(from: $0.range.length) } ?? line
            return allAtLevel ? stripped : marks + stripped
        }
        return TextEdit(range: lines, replacement: updated, selection: endSelection(lines, original, updated, selection))
    }

    /// Adds `prefix` to every touched line, or removes it when all lines already have it.
    /// List prefixes replace any existing list marker.
    public static func toggleLinePrefix(_ prefix: LinePrefix, in text: NSString, selection: NSRange) -> TextEdit {
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        let marker = try! NSRegularExpression(pattern: #"^([ \t]*)((?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?|>[ \t]?)"#)
        let contentLines = original.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        func has(_ line: String) -> Bool {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            switch prefix {
            case .blockquote: return trimmed.hasPrefix(">")
            case .bullet: return (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")) && !trimmed.dropFirst(2).hasPrefix("[")
            case .numbered: return trimmed.first?.isNumber == true && trimmed.contains(". ")
            case .task: return trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")
            }
        }
        let removing = !contentLines.isEmpty && contentLines.allSatisfy(has)
        var number = 0
        let updated = mapLines(original) { line in
            guard !line.isEmpty else { return line }
            let ns = line as NSString
            let match = marker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            let indent = match.map { ns.substring(with: $0.range(at: 1)) } ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let body = match.map { ns.substring(from: $0.range.length) } ?? String(line.dropFirst(indent.count))
            if removing { return indent + body }
            number += 1
            switch prefix {
            case .blockquote: return "> " + line
            case .bullet: return indent + "- " + body
            case .numbered: return indent + "\(number). " + body
            case .task: return indent + "- [ ] " + body
            }
        }
        return TextEdit(range: lines, replacement: updated, selection: endSelection(lines, original, updated, selection))
    }

    /// Fences the touched lines in ```` ``` ````; with an empty selection on an empty line, inserts an
    /// empty fence with the cursor inside.
    public static func codeBlock(in text: NSString, selection: NSRange) -> TextEdit {
        if selection.length == 0 {
            let line = text.lineRange(for: selection)
            let content = text.substring(with: NSRange(location: line.location, length: lineContentEnd(text, line) - line.location))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "```\n\n```",
                                selection: NSRange(location: selection.location + 4, length: 0))
            }
        }
        let lines = text.lineRange(for: selection)
        let end = lineContentEnd(text, NSRange(location: lines.location, length: lines.length))
        let body = text.substring(with: NSRange(location: lines.location, length: end - lines.location))
        let replacement = "```\n" + body + "\n```"
        return TextEdit(range: NSRange(location: lines.location, length: end - lines.location), replacement: replacement,
                        selection: NSRange(location: lines.location + 4, length: (body as NSString).length))
    }

    // MARK: Helpers

    /// End of the line's content, excluding its line terminator.
    static func lineContentEnd(_ text: NSString, _ line: NSRange) -> Int {
        var end = NSMaxRange(line)
        while end > line.location {
            let c = text.character(at: end - 1)
            if c == 0x0A || c == 0x0D { end -= 1 } else { break }
        }
        return end
    }

    /// Applies `transform` to each line of `block`, keeping the line terminators.
    static func mapLines(_ block: String, _ transform: (String) -> String) -> String {
        var lines = block.components(separatedBy: "\n")
        let trailing = lines.last == ""
        if trailing { lines.removeLast() }
        return lines.map(transform).joined(separator: "\n") + (trailing ? "\n" : "")
    }

    static func hasTrailingNewline(_ s: String) -> Bool { s.hasSuffix("\n") }

    /// Keeps a caret on the same line after a whole-line rewrite; otherwise selects the rewritten lines.
    static func endSelection(_ lines: NSRange, _ original: String, _ updated: String, _ selection: NSRange) -> NSRange {
        let updatedLength = (updated as NSString).length - (hasTrailingNewline(updated) ? 1 : 0)
        if selection.length == 0 {
            let delta = (updated as NSString).length - (original as NSString).length
            return NSRange(location: min(lines.location + updatedLength, max(lines.location, selection.location + delta)), length: 0)
        }
        return NSRange(location: lines.location, length: updatedLength)
    }

    /// The word (letters, digits, `_`) touching `location`, if any.
    static func word(in text: NSString, at location: Int) -> NSRange? {
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < text.length, let scalar = Unicode.Scalar(text.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        var start = location
        var end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
