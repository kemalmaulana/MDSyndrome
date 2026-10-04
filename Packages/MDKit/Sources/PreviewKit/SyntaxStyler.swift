import Foundation
import SwiftUI
import SyntaxHighlighting

/// Highlighted code as an AttributedString, cached because SwiftUI re-evaluates bodies often.
@MainActor
enum SyntaxStyler {
    private static let cache = NSCache<NSString, Box>()

    final class Box {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    static func attributed(_ code: String, language: String?, theme: PreviewTheme) -> AttributedString {
        let key = "\(language ?? "")|\(theme.name)|\(code)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        var result = AttributedString()
        for segment in Highlighter.highlight(code, language: language) {
            var run = AttributedString(segment.text)
            if let kind = segment.kind { run.foregroundColor = theme.syntax.color(for: kind).color }
            result += run
        }
        cache.setObject(Box(result), forKey: key)
        return result
    }
}
