import Foundation

extension String {
    /// `\r\n` and lone `\r` turned into `\n`. cmark treats all three as line ends, but Swift sees
    /// `"\r\n"` as one Character, so splitting on `"\n"` would miss every Windows line ending.
    var normalizedLineEndings: String {
        guard utf8.contains(UInt8(ascii: "\r")) else { return self }
        return replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
