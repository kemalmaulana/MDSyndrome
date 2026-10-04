import Testing
@testable import SyntaxHighlighting

/// Shorthand: every coloured segment as "text=kind", in order (plain text is left out).
private func colored(_ code: String, _ language: String) -> [String] {
    Highlighter.highlight(code, language: language)
        .compactMap { segment in segment.kind.map { "\(segment.text)=\($0.rawValue)" } }
}

@Suite struct HighlighterBasicsTests {
    @Test(arguments: ["swift", "js", "ts", "python", "go", "rust", "c", "cpp", "objc", "cs", "java", "kotlin", "dart", "ruby", "php", "sh", "json", "yaml", "toml", "sql", "css", "html", "diff"])
    func segmentsReassembleTheInputExactly(_ language: String) {
        let code = "let x = \"str\" // c\n/* b */ 42 'q' <a href=\"u\">t</a> +add\n-del $VAR @attr #if key: v\n"
        #expect(Highlighter.highlight(code, language: language).map(\.text).joined() == code)
        #expect(Highlighter.supports(language))
    }

    @Test func unknownLanguageIsOnePlainSegment() {
        #expect(Highlighter.highlight("anything at all", language: "klingon") == [HighlightSegment(text: "anything at all", kind: nil)])
        #expect(Highlighter.highlight("x", language: nil) == [HighlightSegment(text: "x", kind: nil)])
        #expect(Highlighter.highlight("", language: "swift").isEmpty)
    }

    @Test func languageNamesAreCaseInsensitive() {
        #expect(Highlighter.supports("Swift"))
        #expect(Highlighter.supports("JSON"))
        #expect(!Highlighter.supports("klingon"))
    }

    @Test func adjacentSegmentsOfTheSameKindAreMerged() {
        #expect(Highlighter.highlight("a + b", language: "swift") == [HighlightSegment(text: "a + b", kind: nil)])
    }
}

@Suite struct HighlighterLanguageTests {
    @Test func swift() {
        #expect(colored(#"@MainActor func f() -> String { return "hi" } // done"#, "swift") == [
            "@MainActor=attribute", "func=keyword", "String=type", "return=keyword", #""hi"=string"#, "// done=comment",
        ])
    }

    @Test func swiftNumbersAndRanges() {
        #expect(colored("1..<10 0x1F 1e-9 1_000", "swift") == ["1=number", "10=number", "0x1F=number", "1e-9=number", "1_000=number"])
    }

    @Test func swiftMultilineString() {
        let code = "let s = \"\"\"\nline \"one\"\n\"\"\""
        #expect(colored(code, "swift") == ["let=keyword", "\"\"\"\nline \"one\"\n\"\"\"=string"])
    }

    @Test func javascriptTemplateLiteralSpansLines() {
        #expect(colored("const t = `a\nb`;", "js") == ["const=keyword", "`a\nb`=string"])
    }

    @Test func pythonDecoratorTripleQuoteAndComment() {
        let code = "@cache\ndef f():\n    '''doc'''  # c\n    return None"
        #expect(colored(code, "python") == ["@cache=attribute", "def=keyword", "'''doc'''=string", "# c=comment", "return=keyword", "None=literal"])
    }

    @Test func rustLifetimeIsNotAStringButCharIs() {
        #expect(colored("fn f<'a>(x: &'a str) -> char { 'z' }", "rust") == ["fn=keyword", "str=type", "char=type", "'z'=string"])
        #expect(colored(#"let c = '\u{1F600}';"#, "rust") == ["let=keyword", #"'\u{1F600}'=string"#])
    }

    @Test func cPreprocessorAndCharLiteral() {
        #expect(colored(#"#include <stdio.h>"# + "\n" + #"char c = '\n';"#, "c") == ["#include=attribute", "char=type", #"'\n'=string"#])
    }

    @Test func jsonKeysAreAttributesAndValuesAreStrings() {
        #expect(colored(#"{"name": "md", "ok": true, "n": 1.5}"#, "json") == [
            #""name"=attribute"#, #""md"=string"#, #""ok"=attribute"#, "true=literal", #""n"=attribute"#, "1.5=number",
        ])
    }

    @Test func yamlKeysCommentsAndLiterals() {
        #expect(colored("runs-on: macos-latest # ci\nenabled: true", "yaml") == ["runs-on=attribute", "# ci=comment", "enabled=attribute", "true=literal"])
    }

    @Test func cssPropertiesAreAttributes() {
        #expect(colored(".a { color: #fff; margin: 10px; }", "css") == ["color=attribute", "margin=attribute", "10px=number"])
    }

    @Test func sqlKeywordsIgnoreCase() {
        #expect(colored("SELECT id FROM t WHERE x = 'a' -- note", "sql") == ["SELECT=keyword", "FROM=keyword", "WHERE=keyword", "'a'=string", "-- note=comment"])
        #expect(colored("select 1", "sql") == ["select=keyword", "1=number"])
    }

    @Test func shellVariablesAndComments() {
        #expect(colored(#"echo "$HOME" ${PATH} # list"#, "sh") == [#""$HOME"=string"#, "${PATH}=attribute", "# list=comment"])
    }

    @Test func htmlTagsAttributesValuesCommentsEntities() {
        #expect(colored(#"<a href="x">A &amp; B</a><!-- c -->"#, "html") == [
            "<a=tag", "href=attribute", #""x"=string"#, ">=tag", "&amp;=literal", "</a>=tag", "<!-- c -->=comment",
        ])
    }

    @Test func diffLines() {
        #expect(colored("@@ -1 +1 @@\n-old\n+new\n same", "diff") == ["@@ -1 +1 @@=meta", "-old=deleted", "+new=inserted"])
    }
}

@Suite struct HighlighterRobustnessTests {
    @Test func unterminatedStringAndCommentRunToTheEnd() {
        #expect(Highlighter.highlight("let s = \"open", language: "swift").last == HighlightSegment(text: "\"open", kind: .string))
        #expect(Highlighter.highlight("x /* never closed\nmore", language: "swift").last == HighlightSegment(text: "/* never closed\nmore", kind: .comment))
    }

    @Test func singleLineStringsStopAtLineEnd() {
        let segments = Highlighter.highlight("x = 'open\ny = 1", language: "python")
        #expect(segments.contains(HighlightSegment(text: "'open", kind: .string)))
        #expect(segments.contains(HighlightSegment(text: "1", kind: .number)))
    }

    @Test func largeInputIsLinear() {
        let code = String(repeating: "let value = \"text\" + 42 // comment\n", count: 30_000)   // ~1 MB
        let elapsed = ContinuousClock().measure { _ = Highlighter.highlight(code, language: "swift") }
        #expect(elapsed < .seconds(3), "measured \(elapsed)")
    }
}
