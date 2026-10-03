import Testing
@testable import MarkdownCore

@Suite struct BlockIdentityTests {
    @Test func idsAreStableWhenOtherBlocksChange() {
        let before = MarkdownParser.parse("# Title\n\nPara one\n\nPara two").blocks
        let after = MarkdownParser.parse("# Title\n\nPara one EDITED\n\nPara two").blocks
        #expect(before[0].id == after[0].id)
        #expect(before[1].id != after[1].id)
        #expect(before[2].id == after[2].id)
    }

    @Test func idsSurviveLinesShiftingDown() {
        let before = MarkdownParser.parse("Para two").blocks
        let after = MarkdownParser.parse("New first\n\nPara two").blocks
        #expect(before[0].id == after[1].id)
    }

    @Test func duplicateBlocksGetDistinctIds() {
        let blocks = MarkdownParser.parse("same\n\nsame\n\nsame").blocks
        #expect(Set(blocks.map(\.id)).count == 3)
    }

    @Test func idsAreDeterministicAcrossParses() {
        #expect(MarkdownParser.parse("x").blocks[0].id == MarkdownParser.parse("x").blocks[0].id)
    }
}
