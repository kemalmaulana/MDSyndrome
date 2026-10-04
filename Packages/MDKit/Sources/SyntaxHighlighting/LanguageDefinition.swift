/// Declarative description of a language for the table-driven lexer.
struct LanguageDefinition: Sendable {
    enum Mode: Sendable { case code, markup, diff }

    var mode: Mode = .code
    var keywords: Set<String> = []
    /// Built-in type names (also see `capitalizedIsType`).
    var types: Set<String> = []
    /// true / false / nil / null / None …
    var literals: Set<String> = []
    var lineComments: [String] = []
    var blockComments: [(open: String, close: String)] = []
    /// Longest first is not required; the lexer tries longer delimiters first.
    var stringDelimiters: [String] = ["\""]
    /// `'` starts a character literal only when it closes within a few characters (Rust lifetimes, C chars).
    var singleQuoteIsChar = false
    var caseInsensitiveKeywords = false
    /// Identifiers starting with an uppercase letter are types (Swift, Java, Kotlin, C#, TS, Rust, Dart).
    var capitalizedIsType = false
    /// `@decorator`, `#if`, `#[derive]`: prefix + identifier is an attribute.
    var attributePrefixes: Set<Character> = []
    /// `$name` (shell, PHP, Perl-ish) is a variable, shown as an attribute.
    var variablePrefix: Character? = nil
    /// Extra characters allowed inside identifiers (`-` in CSS/YAML keys, `$` in JS).
    var identifierExtras: Set<Character> = []
    /// An identifier or string followed by `:` is a key/property (JSON, YAML, CSS).
    var keysBeforeColon = false
}
