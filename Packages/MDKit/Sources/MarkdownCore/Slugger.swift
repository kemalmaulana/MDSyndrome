import Foundation

/// GitHub-compatible heading anchors (same algorithm as github-slugger):
/// lowercase, drop punctuation/symbols, spaces → "-", duplicates get "-1", "-2", …
public struct Slugger: Sendable {
    private var occurrences: [String: Int] = [:]

    public init() {}

    public mutating func slug(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.filter { scalar in
            scalar == " " || scalar == "-" || scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
        let base = String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
        var result = base
        while occurrences[result] != nil {
            occurrences[base, default: 0] += 1
            result = "\(base)-\(occurrences[base]!)"
        }
        occurrences[result] = 0
        return result
    }
}
