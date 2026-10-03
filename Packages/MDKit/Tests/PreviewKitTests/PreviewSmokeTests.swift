import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

/// Renders every block kind once, to catch layout crashes (e.g. recursive views, empty tables).
@MainActor
@Suite struct PreviewSmokeTests {
    static let kitchenSink = """
    # Heading 1
    ## Heading 2
    Paragraph with *em*, **strong**, ~~strike~~, `code`, [link](https://example.com), $x^2$ and a note[^1].

    > Quote
    > > Nested quote

    1. one
    2. two
       - nested
    - [x] done
    - [ ] todo
    -

    ```swift
    let x = 1
    ```

    | a | b |
    |:-:|--:|
    | 1 | 2 |
    | only |

    | empty |
    |---|

    $$
    E = mc^2
    $$

    <div>html</div>

    ---

    ![missing](does-not-exist.png)

    [^1]: Footnote.
    """

    @Test func everyBlockKindRenders() throws {
        let rendered = MarkdownPipeline.render(Self.kitchenSink, options: .default)
        let content = VStack(alignment: .leading) {
            ForEach(rendered.document.blocks) { BlockView(block: $0) }
        }
        .frame(width: 600)
        .environment(\.previewTheme, .github)
        let renderer = ImageRenderer(content: content)
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 600)
        #expect(image.size.height > 200)
    }

    @Test func deeplyNestedQuotesRenderWithoutCrashing() throws {
        let rendered = MarkdownPipeline.render(String(repeating: ">", count: 200) + " deep", options: .default)
        let content = VStack { ForEach(rendered.document.blocks) { BlockView(block: $0) } }
            .frame(width: 600)
        #expect(ImageRenderer(content: content).nsImage != nil)
    }
}
