import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

@Suite struct ImageRowTests {
    private func row(_ md: String) -> [RowImage]? {
        guard case .paragraph(let content)? = MarkdownParser.parse(md).blocks.first?.kind else { return nil }
        return content.imageRow
    }

    @Test func badgeRowWithLinkedAndBareImages() {
        let md = "[![CI](https://img.shields.io/ci.svg)](https://github.com/x/y/actions) ![License](mit.svg)\n![Swift](swift.svg)"
        #expect(row(md) == [
            RowImage(source: "https://img.shields.io/ci.svg", alt: "CI", link: "https://github.com/x/y/actions"),
            RowImage(source: "mit.svg", alt: "License", link: nil),
            RowImage(source: "swift.svg", alt: "Swift", link: nil),
        ])
    }

    @Test func textMixedWithImagesIsNotARow() {
        #expect(row("Build ![CI](ci.svg) passing") == nil)
        #expect(row("[docs](https://example.com) ![CI](ci.svg)") == nil)
    }

    @Test func plainTextIsNotARow() {
        #expect(row("just text") == nil)
    }
}

@MainActor
@Suite(.requiresWindowServer) struct ImageRowRenderTests {
    @Test func badgeRowWrapsWithoutCrashing() throws {
        let md = (1...12).map { "[![b\($0)](missing-\($0).svg)](https://example.com/\($0))" }.joined(separator: " ")
        let rendered = MarkdownPipeline.render(md, options: .default)
        // Offscreen, images are still in their 40 pt loading state (~16 pt wide each), so a
        // 100 pt-wide container must wrap the 12 items over several rows.
        let content = VStack { ForEach(rendered.document.blocks) { BlockView(block: $0) } }.frame(width: 100)
        let image = try #require(ImageRenderer(content: content).nsImage)
        #expect(image.size.height > 80, "12 items cannot fit one 100 pt row, so the row wraps")
    }
}
