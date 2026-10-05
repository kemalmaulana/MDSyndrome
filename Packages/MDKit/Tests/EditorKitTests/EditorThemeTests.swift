import AppKit
import Foundation
import Testing
@testable import EditorKit

@Suite struct EditorThemeTests {
    @Test func builtInThemesMatchMacDown() {
        #expect(EditorTheme.builtIn.map(\.name) == ["Tomorrow+", "Tomorrow", "Solarized (Light)", "Solarized (Dark)", "Mou Paper", "Writer"])
        #expect(Set(EditorTheme.builtIn.map(\.id)).count == 6)
        #expect(EditorTheme.builtIn.first == .tomorrowPlus, "Tomorrow+ is the default")
    }

    @Test func theStorageKeyIsStable() {
        #expect(EditorTheme.storageKey == "editorTheme", "renaming it would reset everyone's chosen theme")
    }

    @Test func unknownNamesFallBackToTheDefault() {
        #expect(EditorTheme.named("Solarized (Dark)") == .solarizedDark)
        #expect(EditorTheme.named("No Such Theme") == .tomorrowPlus)
        #expect(EditorTheme.named("") == .tomorrowPlus)
    }

    @Test func everyThemeStylesEveryKindAndUsesValidColours() {
        for theme in EditorTheme.builtIn {
            for hex in [theme.background, theme.foreground, theme.caret] + [theme.selectionBackground, theme.selectionForeground].compactMap({ $0 }) {
                #expect(editorColor(hex) != nil, "\(theme.name): bad colour \(hex)")
            }
            for kind in EditorTokenKind.allCases {
                let style = theme.style(for: kind)
                #expect(style != nil, "\(theme.name) has no style for \(kind)")
                for hex in [style?.color, style?.background].compactMap({ $0 }) {
                    #expect(editorColor(hex) != nil, "\(theme.name) \(kind): bad colour \(hex)")
                }
            }
        }
    }

    @Test func tomorrowPlusEnlargesHeadingsAndOnlyBoldsTheFirstTwo() throws {
        let sizes = try (1...6).map { try #require(EditorTheme.tomorrowPlus.style(for: EditorTokenKind(rawValue: "heading\($0)")!)?.sizeScale) }
        #expect(sizes == [24, 20, 17, 15, 13, 11].map { Double($0) / 14 })
        let bold = (1...6).map { EditorTheme.tomorrowPlus.style(for: EditorTokenKind(rawValue: "heading\($0)")!)?.bold }
        #expect(bold == [true, true, false, false, false, false])
        #expect(EditorTheme.tomorrow.style(for: .heading1)?.sizeScale == nil)
        #expect(EditorTheme.tomorrow.style(for: .heading4)?.bold == true)
    }

    @Test func themesKnowWhetherTheyAreDark() {
        #expect(EditorTheme.tomorrowPlus.isDark)
        #expect(EditorTheme.tomorrow.isDark)
        #expect(EditorTheme.solarizedDark.isDark)
        #expect(!EditorTheme.solarizedLight.isDark)
        #expect(!EditorTheme.mouPaper.isDark)
        #expect(!EditorTheme.writer.isDark)
    }

    @Test func themesRoundTripThroughJSON() throws {
        for theme in EditorTheme.builtIn {
            let data = try JSONEncoder().encode(theme)
            #expect(try JSONDecoder().decode(EditorTheme.self, from: data) == theme)
        }
    }

    @Test func aHandWrittenThemeDecodes() throws {
        let json = """
        {"name": "Mine", "background": "#101010", "foreground": "#eeeeee", "caret": "#ff0000",
         "styles": {"heading1": {"color": "#00ff00", "bold": true, "sizeScale": 1.5}, "code": {"background": "#333333ff"}}}
        """
        let theme = try JSONDecoder().decode(EditorTheme.self, from: Data(json.utf8))
        #expect(theme.name == "Mine")
        #expect(theme.selectionBackground == nil)
        #expect(theme.style(for: .heading1) == EditorTokenStyle(color: "#00ff00", bold: true, sizeScale: 1.5))
        #expect(theme.style(for: .emphasis) == nil)
    }

    @Test func hexColours() throws {
        let colour = try #require(editorColor("#2d2d2d"))
        #expect(abs(colour.redComponent - 45.0 / 255) < 0.001)
        #expect(colour.alphaComponent == 1)
        #expect(abs(try #require(editorColor("ffcc6640")).alphaComponent - 64.0 / 255) < 0.001, "the # is optional and 8 digits add alpha")
        #expect(editorColor("#12345") == nil)
        #expect(editorColor("#gggggg") == nil)
        #expect(editorColor("") == nil)
        #expect(editorColor(nil) == nil)
    }
}
