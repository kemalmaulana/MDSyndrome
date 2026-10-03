/// Everything the UI needs from one parse. Produced off the main actor.
public struct RenderedDocument: Hashable, Sendable {
    public let document: MarkdownDocument
    public let outline: [OutlineItem]
    public let stats: DocumentStats

    public init(document: MarkdownDocument, outline: [OutlineItem], stats: DocumentStats) {
        self.document = document
        self.outline = outline
        self.stats = stats
    }

    public static let empty = RenderedDocument(document: MarkdownDocument(blocks: []), outline: [], stats: .empty)
}

public enum MarkdownPipeline {
    public static func render(_ text: String, options: MarkdownOptions) -> RenderedDocument {
        let document = MarkdownParser.parse(text, options: options)
        return RenderedDocument(
            document: document,
            outline: Outline.make(from: document),
            stats: DocumentStats.make(source: text, document: document)
        )
    }
}
