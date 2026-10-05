import AppKit

/// Colours Markdown source in an NSTextStorage as it changes.
///
/// It remembers the multi-line state (code fence, math block, comment, front matter) at the start of
/// every line. An edit re-colours the edited lines, then keeps going only while the state at the
/// next line differs from what was remembered, so typing in a paragraph touches one line and
/// opening a code fence recolours down to its closing fence. Long runs are split into passes of
/// `maxLinesPerPass` lines; the rest follows on the next run-loop turn, so a keystroke never waits
/// on a whole 1 MB document.
@MainActor
public final class EditorHighlighter: NSObject, NSTextStorageDelegate {
    public var theme: EditorTheme { didSet { styleSheet = nil } }
    public var configuration: EditorConfiguration { didSet { styleSheet = nil } }

    /// Lines coloured before yielding to the run loop.
    public var maxLinesPerPass = 1500

    /// Called after every change to the characters (typing, paste, undo, programmatic edits), once the
    /// colouring has caught up. The coordinator uses it to keep the document model in step.
    var onCharactersChanged: (@MainActor () -> Void)?

    private weak var storage: NSTextStorage?
    private var index = LineIndex()
    /// The state at the start of each line, parallel to `index`.
    private var states: [LineState] = [.documentStart]
    /// First line still to be (re)coloured; nil when everything is up to date.
    private var pendingFrom: Int?
    /// Lines up to here must be coloured even if the state seems unchanged: the edited lines, and the
    /// line where a cut-short pass stopped (its remembered state is already the new one, but its
    /// colours are still the old ones, so "same state as remembered" proves nothing up to there).
    private var mustReach = -1
    private var continuationScheduled = false
    private var styleSheet: StyleSheet?

    public init(theme: EditorTheme, configuration: EditorConfiguration) {
        self.theme = theme
        self.configuration = configuration
        super.init()
    }

    /// Starts following `storage`: colours it now and updates it after every edit.
    public func attach(to storage: NSTextStorage) {
        self.storage = storage
        storage.delegate = self
        restyleAll()
    }

    public var isUpToDate: Bool { pendingFrom == nil }
    var lineCount: Int { index.lineCount }
    var lineStates: [LineState] { states }

    /// The state at the start of the line containing `location`.
    func lineState(at location: Int) -> LineState? {
        guard !states.isEmpty else { return nil }
        return states[index.line(containing: Swift.max(0, Swift.min(location, index.length)))]
    }

    /// Colours everything again (new document, theme or font change).
    public func restyleAll() {
        guard let storage else { return }
        let text = storage.mutableString
        index = LineIndex(text)
        states = [.documentStart] + Array(repeating: .normal, count: index.lineCount - 1)
        storage.setAttributes(sheet.base, range: NSRange(location: 0, length: storage.length))
        pendingFrom = 0
        mustReach = index.lineCount - 1
        runPass()
    }

    /// Finishes any colouring left over from a long run. The run loop does this by itself; tests and
    /// callers that need the final result call it directly.
    public func finishPending() {
        while pendingFrom != nil {
            let before = pendingFrom
            continueHighlighting()
            if pendingFrom == before { break }   // defensive: never spin
        }
    }

    // MARK: - Following edits

    nonisolated public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                        range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            didEdit(editedRange: editedRange, changeInLength: delta)
            onCharactersChanged?()
        }
    }

    func didEdit(editedRange: NSRange, changeInLength delta: Int) {
        guard let storage else { return }
        let text = storage.mutableString
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        // The line list must describe the text as it was before this edit; if it doesn't, start over.
        guard index.length == text.length - delta, oldRange.length >= 0, NSMaxRange(oldRange) <= index.length else {
            return restyleAll()
        }
        let change = index.replace(oldRange, with: text.substring(with: editedRange) as NSString)
        states.replaceSubrange((change.first + 1)..<(change.first + 1 + change.removed),
                               with: repeatElement(LineState.normal, count: change.inserted))

        func shifted(_ line: Int) -> Int {
            if line <= change.first { return line }
            if line <= change.first + change.removed { return change.first }
            return line - change.removed + change.inserted
        }
        pendingFrom = Swift.min(pendingFrom.map(shifted) ?? .max, change.first)
        mustReach = Swift.max(shifted(mustReach), change.first + change.inserted)

        // New characters inherit whatever styling sat under the caret. Neutralise them now, so a
        // paste that outlasts one pass doesn't show heading-sized or coloured text meanwhile.
        storage.setAttributes(sheet.base, range: editedRange)
        runPass()
    }

    // MARK: - Colouring

    /// Continues a pass that stopped at its line budget.
    func continueHighlighting() {
        guard let storage, pendingFrom != nil else { return }
        storage.beginEditing()
        runPass()
        storage.endEditing()
    }

    private func scheduleContinuation() {
        guard !continuationScheduled else { return }
        continuationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            continuationScheduled = false
            continueHighlighting()
        }
    }

    private func runPass() {
        guard let storage, var line = pendingFrom else { return }
        let text = storage.mutableString
        var budget = maxLinesPerPass
        while line < index.lineCount {
            let next = colour(line: line, state: states[line], in: storage, text: text)
            line += 1
            guard line < index.lineCount else { break }
            if line > mustReach, states[line] == next {   // the rest was coloured under this very state
                finish()
                return
            }
            states[line] = next
            budget -= 1
            if budget <= 0 {
                pendingFrom = line
                mustReach = Swift.max(mustReach, line)
                scheduleContinuation()
                return
            }
        }
        finish()
    }

    private func finish() {
        pendingFrom = nil
        mustReach = -1
    }

    /// Applies base + token attributes to one line (including its terminator); returns the next line's state.
    private func colour(line: Int, state: LineState, in storage: NSTextStorage, text: NSString) -> LineState {
        let sheet = self.sheet
        let full = index.range(ofLine: line)
        let content = index.contentRange(ofLine: line)
        storage.setAttributes(sheet.base, range: full)
        let (tokens, next) = SourceHighlighter.tokens(line: text.substring(with: content), state: state)
        let headingLevel = tokens.first.map { sheet.headingNumber(of: $0.kind) } ?? 0
        for token in tokens {
            let attributes = sheet.attributes(for: token.kind, headingLevel: headingLevel)
            guard !attributes.isEmpty else { continue }
            let range = NSRange(location: content.location + token.range.location, length: token.range.length)
            guard range.location >= content.location, NSMaxRange(range) <= NSMaxRange(content) else { continue }
            storage.addAttributes(attributes, range: range)
        }
        return next
    }

    private var sheet: StyleSheet {
        if let styleSheet { return styleSheet }
        let made = StyleSheet(theme: theme, configuration: configuration)
        styleSheet = made
        return made
    }
}

/// Theme + configuration resolved into attribute dictionaries, built once per change.
final class StyleSheet {
    let base: [NSAttributedString.Key: Any]
    private let theme: EditorTheme
    private let font: NSFont
    private var cache: [CacheKey: [NSAttributedString.Key: Any]] = [:]

    private struct CacheKey: Hashable {
        let kind: EditorTokenKind
        let heading: Int
    }

    private static let headings: [EditorTokenKind] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]

    init(theme: EditorTheme, configuration: EditorConfiguration) {
        self.theme = theme
        font = configuration.font
        base = configuration.textAttributes(foreground: editorColor(theme.foreground) ?? .textColor)
    }

    /// 1…6 for the heading kinds, 0 for everything else.
    func headingNumber(of kind: EditorTokenKind) -> Int {
        (Self.headings.firstIndex(of: kind) ?? -1) + 1
    }

    /// Attributes for `kind`. Inside a heading line (`headingLevel` 1…6) emphasis, code and the
    /// like keep the heading's size and weight instead of falling back to body text.
    func attributes(for kind: EditorTokenKind, headingLevel: Int) -> [NSAttributedString.Key: Any] {
        let key = CacheKey(kind: kind, heading: headingLevel)
        if let cached = cache[key] { return cached }
        let built = build(kind, headingLevel: headingLevel)
        cache[key] = built
        return built
    }

    private func build(_ kind: EditorTokenKind, headingLevel: Int) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if kind == .strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let style = theme.style(for: kind)
        if let color = editorColor(style?.color) { attributes[.foregroundColor] = color }
        if let background = editorColor(style?.background) { attributes[.backgroundColor] = background }

        var bold = style?.bold ?? false
        let italic = style?.italic ?? false
        var scale = style?.sizeScale ?? 1
        if headingLevel > 0, headingNumber(of: kind) == 0, let heading = theme.style(for: Self.headings[headingLevel - 1]) {
            bold = bold || heading.bold == true
            scale = heading.sizeScale ?? scale
        }
        if bold || italic || scale != 1 {
            attributes[.font] = styled(bold: bold, italic: italic, scale: scale)
        }
        return attributes
    }

    private func styled(bold: Bool, italic: Bool, scale: Double) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize * scale) ?? font
    }
}
