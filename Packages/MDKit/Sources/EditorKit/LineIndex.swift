import Foundation

/// Where every line of a text starts. A line is whatever sits between `\n` characters, which is
/// also how the document model splits lines (CRLF is normalised on load). Locations are UTF-16.
///
/// Kept in step with the text through `replace`, so finding the line at a location is a binary
/// search and an edit shifts offsets instead of rescanning the document.
struct LineIndex: Equatable {
    /// Start of each line. Always begins with 0; a trailing "\n" yields a final empty line.
    private(set) var starts: [Int] = [0]
    private(set) var length = 0

    /// What one edit did to the line list: line `first` is the first line the edit touches; the
    /// `removed` lines after it are gone and `inserted` new lines follow it.
    struct Change: Equatable {
        let first: Int
        let removed: Int
        let inserted: Int
    }

    init() {}

    init(_ text: NSString) {
        length = text.length
        guard length > 0 else { return }
        var buffer = [unichar](repeating: 0, count: length)
        text.getCharacters(&buffer, range: NSRange(location: 0, length: length))
        for (offset, unit) in buffer.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
    }

    var lineCount: Int { starts.count }

    /// Index of the line containing `location` (a location at the very end belongs to the last line).
    func line(containing location: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The line's range including its "\n".
    func range(ofLine index: Int) -> NSRange {
        let start = starts[index]
        let end = index + 1 < starts.count ? starts[index + 1] : length
        return NSRange(location: start, length: end - start)
    }

    /// The line's range without its "\n".
    func contentRange(ofLine index: Int) -> NSRange {
        let full = range(ofLine: index)
        let hasNewline = index + 1 < starts.count
        return NSRange(location: full.location, length: full.length - (hasNewline ? 1 : 0))
    }

    /// Applies one edit: `range` (in the old text) was replaced by `newText`.
    @discardableResult
    mutating func replace(_ range: NSRange, with newText: NSString) -> Change {
        let first = line(containing: range.location)
        let lastOld = line(containing: NSMaxRange(range))
        let delta = newText.length - range.length

        // A line start s exists because the character before it is "\n". Those with
        // range.location < s <= NSMaxRange(range) sat inside the replaced text, so they go away
        // (lines first+1 ... lastOld). Later starts just move by the length change.
        var tail = Array(starts[(lastOld + 1)...])
        for i in tail.indices { tail[i] += delta }

        var inserted: [Int] = []
        if newText.length > 0 {
            var buffer = [unichar](repeating: 0, count: newText.length)
            newText.getCharacters(&buffer, range: NSRange(location: 0, length: newText.length))
            for (offset, unit) in buffer.enumerated() where unit == 0x0A {
                inserted.append(range.location + offset + 1)
            }
        }
        starts = Array(starts[...first]) + inserted + tail
        length += delta
        return Change(first: first, removed: lastOld - first, inserted: inserted.count)
    }
}
