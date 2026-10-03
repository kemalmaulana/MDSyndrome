import Foundation
import Testing
@testable import PreviewKit

@Suite struct ThemeColorTests {
    @Test func parsesSixAndEightDigitHex() throws {
        let opaque = try #require(ThemeColor.rgba(hex: "#ff8000"))
        #expect(opaque.r == 1 && opaque.b == 0 && opaque.a == 1)
        #expect(abs(opaque.g - 128.0 / 255) < 0.0001)
        let translucent = try #require(ThemeColor.rgba(hex: "00000080"))
        #expect(abs(translucent.a - 128.0 / 255) < 0.0001)
    }

    @Test(arguments: ["", "#fff", "#gggggg", "#12345", "#1234567890"])
    func rejectsMalformedHex(_ hex: String) {
        #expect(ThemeColor.rgba(hex: hex) == nil)
    }
}

@Suite struct PreviewThemeTests {
    @Test func headingSizesClampLevel() {
        let theme = PreviewTheme.github
        #expect(theme.headingSize(level: 1) == 32)
        #expect(theme.headingSize(level: 0) == 32)
        #expect(theme.headingSize(level: 9) == theme.headingSize(level: 6))
    }

    @Test func themeRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(PreviewTheme.github)
        #expect(try JSONDecoder().decode(PreviewTheme.self, from: data) == .github)
    }
}
