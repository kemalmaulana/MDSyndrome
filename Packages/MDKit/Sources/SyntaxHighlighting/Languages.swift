/// The built-in language table. Keys are lowercase fence-info words; aliases map to the same definition.
enum Languages {
    static func definition(for name: String) -> LanguageDefinition? {
        table[name.lowercased()]
    }

    private static let table: [String: LanguageDefinition] = {
        var table: [String: LanguageDefinition] = [:]
        func add(_ names: [String], _ definition: LanguageDefinition) {
            for name in names { table[name] = definition }
        }
        let cComments: [(open: String, close: String)] = [("/*", "*/")]

        add(["swift"], LanguageDefinition(
            keywords: words("actor any as associatedtype async await break case catch class continue convenience default defer deinit didSet do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect init inout internal is lazy let macro mutating nonisolated open operator optional override package private protocol public repeat required rethrows return set some static struct subscript super switch throw throws try typealias unowned var weak where while willSet"),
            types: words("Any AnyObject Self Int Double Float String Bool Character Void Never"),
            literals: words("true false nil self"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"\"\"", "\""],
            capitalizedIsType: true, attributePrefixes: ["@", "#"]))

        let jsKeywords = "async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch throw try typeof var void while with yield"
        add(["javascript", "js", "jsx", "mjs", "cjs"], LanguageDefinition(
            keywords: words(jsKeywords),
            types: words("Array Object String Number Boolean Promise Map Set Date RegExp Error JSON Math"),
            literals: words("true false null undefined this NaN Infinity"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'", "`"],
            attributePrefixes: ["@"], identifierExtras: ["$"]))
        add(["typescript", "ts", "tsx"], LanguageDefinition(
            keywords: words(jsKeywords + " abstract as declare enum implements interface keyof namespace private protected public readonly type satisfies is infer"),
            types: words("string number boolean any unknown never void object bigint symbol Array Record Partial Promise"),
            literals: words("true false null undefined this"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'", "`"],
            capitalizedIsType: true, attributePrefixes: ["@"], identifierExtras: ["$"]))

        add(["python", "py"], LanguageDefinition(
            keywords: words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda match case nonlocal not or pass raise return try while with yield"),
            types: words("int float str bool list dict set tuple bytes object type Exception"),
            literals: words("True False None self cls"),
            lineComments: ["#"], stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
            attributePrefixes: ["@"]))

        add(["go", "golang"], LanguageDefinition(
            keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
            types: words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any"),
            literals: words("true false nil iota"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "`", "'"],
            singleQuoteIsChar: true))

        add(["rust", "rs"], LanguageDefinition(
            keywords: words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while"),
            types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Self"),
            literals: words("true false self None Some Ok Err"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            singleQuoteIsChar: true, capitalizedIsType: true, attributePrefixes: ["#"]))

        let cKeywords = "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while"
        let cTypes = "char double float int long short signed unsigned void bool size_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t"
        add(["c", "h"], LanguageDefinition(
            keywords: words(cKeywords), types: words(cTypes), literals: words("true false NULL"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            singleQuoteIsChar: true, attributePrefixes: ["#"]))
        add(["cpp", "c++", "cc", "cxx", "hpp"], LanguageDefinition(
            keywords: words(cKeywords + " alignas class constexpr consteval decltype delete explicit friend mutable namespace new noexcept operator override private protected public template this throw try catch typename using virtual co_await co_return co_yield concept requires"),
            types: words(cTypes + " auto string vector map set unique_ptr shared_ptr std"),
            literals: words("true false nullptr NULL"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            singleQuoteIsChar: true, attributePrefixes: ["#"]))
        add(["objective-c", "objc", "objectivec", "m"], LanguageDefinition(
            keywords: words(cKeywords + " self super id instancetype nonatomic atomic strong weak copy assign readonly readwrite nullable nonnull"),
            types: words(cTypes + " BOOL NSInteger NSUInteger CGFloat NSString NSArray NSDictionary"),
            literals: words("YES NO nil NULL true false"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            singleQuoteIsChar: true, attributePrefixes: ["#", "@"]))

        add(["csharp", "cs", "c#"], LanguageDefinition(
            keywords: words("abstract as async await base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly record ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using var virtual void volatile when where while yield"),
            types: words("bool byte char decimal double float int long object sbyte short string uint ulong ushort dynamic"),
            literals: words("true false null"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            singleQuoteIsChar: true, capitalizedIsType: true, attributePrefixes: ["#"]))

        add(["java"], LanguageDefinition(
            keywords: words("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public record return sealed static strictfp super switch synchronized this throw throws transient try var void volatile while yield"),
            types: words("boolean byte char double float int long short String Object Integer List Map"),
            literals: words("true false null"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"\"\"", "\"", "'"],
            singleQuoteIsChar: true, capitalizedIsType: true, attributePrefixes: ["@"]))
        add(["kotlin", "kt", "kts"], LanguageDefinition(
            keywords: words("abstract as break by catch class companion const constructor continue data do else enum external final finally for fun get if import in infix init inline inner interface internal is lateinit noinline object open operator out override package private protected public reified return sealed set super suspend this throw try typealias val var vararg when where while"),
            types: words("Int Long Short Byte Double Float Boolean Char String Unit Any Nothing List Map Set"),
            literals: words("true false null this"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"\"\"", "\"", "'"],
            singleQuoteIsChar: true, capitalizedIsType: true, attributePrefixes: ["@"]))
        add(["dart"], LanguageDefinition(
            keywords: words("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var void when while with yield"),
            types: words("int double num String bool List Map Set Future Stream Object dynamic void Never"),
            literals: words("true false null this"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
            capitalizedIsType: true, attributePrefixes: ["@"], variablePrefix: "$"))

        add(["ruby", "rb"], LanguageDefinition(
            keywords: words("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative attr_accessor attr_reader"),
            literals: words("true false nil"),
            lineComments: ["#"], stringDelimiters: ["\"", "'"],
            capitalizedIsType: true, attributePrefixes: ["@", ":"]))
        add(["php"], LanguageDefinition(
            keywords: words("abstract and as break case catch class clone const continue declare default do echo else elseif enum extends final finally fn for foreach function global if implements include interface match namespace new or private protected public readonly require return static switch throw trait try use var while yield"),
            literals: words("true false null TRUE FALSE NULL"),
            lineComments: ["//", "#"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            capitalizedIsType: true, variablePrefix: "$"))

        add(["shell", "sh", "bash", "zsh", "console", "shellsession", "fish"], LanguageDefinition(
            keywords: words("if then else elif fi for while until do done case esac in function return local export readonly declare unset shift source alias set break continue exit"),
            literals: words("true false"),
            lineComments: ["#"], stringDelimiters: ["\"", "'"],
            variablePrefix: "$", identifierExtras: ["-"]))

        add(["json", "jsonc", "json5"], LanguageDefinition(
            literals: words("true false null"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\""],
            keysBeforeColon: true))
        add(["yaml", "yml"], LanguageDefinition(
            literals: words("true false null yes no on off ~"),
            lineComments: ["#"], stringDelimiters: ["\"", "'"],
            identifierExtras: ["-", "."], keysBeforeColon: true))
        add(["toml"], LanguageDefinition(
            literals: words("true false"),
            lineComments: ["#"], stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
            identifierExtras: ["-", "."]))

        add(["sql", "mysql", "postgresql", "postgres", "sqlite"], LanguageDefinition(
            keywords: words("add all alter and as asc begin between by case check column commit constraint create cross database default delete desc distinct drop else end exists foreign from full group having if in index inner insert into is join key left like limit not null on or order outer primary references returning right rollback select set table then transaction union unique update values view when where with"),
            types: words("int integer bigint smallint decimal numeric float real double varchar char text boolean date time timestamp json jsonb uuid serial"),
            literals: words("true false null"),
            lineComments: ["--"], blockComments: cComments, stringDelimiters: ["'", "\""],
            caseInsensitiveKeywords: true))

        add(["css", "scss", "less"], LanguageDefinition(
            keywords: words("important media import supports keyframes font-face from to and not only"),
            lineComments: ["//"], blockComments: cComments, stringDelimiters: ["\"", "'"],
            attributePrefixes: ["@"], identifierExtras: ["-"], keysBeforeColon: true))

        add(["html", "xml", "svg", "xhtml", "plist", "vue"], LanguageDefinition(mode: .markup))
        add(["diff", "patch"], LanguageDefinition(mode: .diff))
        return table
    }()

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }
}
