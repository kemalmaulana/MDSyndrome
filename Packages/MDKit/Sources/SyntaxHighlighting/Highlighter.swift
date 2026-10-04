/// What a run of source code is, for colouring. `nil` kind in a segment means plain text.
public enum TokenKind: String, Hashable, Sendable, CaseIterable, Codable {
    case keyword, type, literal, string, number, comment, attribute, tag, inserted, deleted, meta
}

/// A contiguous run of code with one kind. Segments cover the input exactly, in order.
public struct HighlightSegment: Hashable, Sendable {
    public let text: String
    public let kind: TokenKind?

    public init(text: String, kind: TokenKind?) {
        self.text = text
        self.kind = kind
    }
}

public enum Highlighter {
    /// Splits `code` into coloured segments for `language` (a fence info word such as "swift" or "js").
    /// Unknown or missing languages return one plain segment.
    public static func highlight(_ code: String, language: String?) -> [HighlightSegment] {
        guard !code.isEmpty else { return [] }
        guard let language, let definition = Languages.definition(for: language) else {
            return [HighlightSegment(text: code, kind: nil)]
        }
        switch definition.mode {
        case .code: return CodeLexer(definition: definition, code: code).run()
        case .markup: return MarkupLexer(code: code).run()
        case .diff: return DiffLexer.run(code)
        }
    }

    /// True when a language name is recognised (directly or through an alias).
    public static func supports(_ language: String) -> Bool {
        Languages.definition(for: language) != nil
    }
}

/// Collects segments, merging neighbours of the same kind. The open run is kept in a mutable buffer
/// so long same-kind runs append in amortised O(1) instead of copying the whole run every time.
struct SegmentBuilder {
    private var finished: [HighlightSegment] = []
    private var runText = ""
    private var runKind: TokenKind?

    mutating func append(_ text: some StringProtocol, _ kind: TokenKind?) {
        guard !text.isEmpty else { return }
        if !runText.isEmpty, kind != runKind {
            finished.append(HighlightSegment(text: runText, kind: runKind))
            runText = ""
        }
        runKind = kind
        runText += text
    }

    var segments: [HighlightSegment] {
        runText.isEmpty ? finished : finished + [HighlightSegment(text: runText, kind: runKind)]
    }
}
