/// Everything the UI needs from one parse. Produced off the main actor.
public struct RenderedDocument: Hashable, Sendable {
    public let document: MarkdownDocument
    public let outline: [OutlineItem]
    public let stats: DocumentStats
    /// Source line ↔ top-level block, for scrolling the editor and the preview together.
    public let sourceMap: SourceMap
    /// Where `#fragment` links point.
    public let anchors: DocumentAnchors

    public init(document: MarkdownDocument, outline: [OutlineItem], stats: DocumentStats,
                sourceMap: SourceMap? = nil, anchors: DocumentAnchors? = nil) {
        self.document = document
        self.outline = outline
        self.stats = stats
        self.sourceMap = sourceMap ?? SourceMap(blocks: document.blocks)
        self.anchors = anchors ?? DocumentAnchors(blocks: document.blocks)
    }

    public static let empty = RenderedDocument(document: MarkdownDocument(blocks: []), outline: [], stats: .empty)
}

public enum MarkdownPipeline {
    public static func render(_ text: String, options: MarkdownOptions) -> RenderedDocument {
        let document = MarkdownParser.parse(text, options: options)
        return RenderedDocument(
            document: document,
            outline: Outline.make(from: document),
            stats: DocumentStats.make(source: text, document: document),
            sourceMap: SourceMap(blocks: document.blocks),
            anchors: DocumentAnchors(blocks: document.blocks)
        )
    }
}
