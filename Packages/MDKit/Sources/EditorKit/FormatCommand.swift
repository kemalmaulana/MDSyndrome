import SwiftUI

/// A Format menu / toolbar action on the editor's text (PRD ED-6, ED-8).
public enum FormatCommand: Hashable, Sendable {
    case bold, italic, strikethrough, highlight, inlineCode, codeBlock, link, image
    case heading(Int)
    case blockquote, bulletList, numberedList, taskList
    case indent, outdent

    /// Every command, in menu order.
    public static let allCases: [FormatCommand] = inline + headings + blocks + indentation

    public static let inline: [FormatCommand] = [.bold, .italic, .strikethrough, .highlight, .inlineCode, .link, .image]
    public static let headings: [FormatCommand] = (1...6).map { .heading($0) }
    public static let blocks: [FormatCommand] = [.blockquote, .bulletList, .numberedList, .taskList, .codeBlock]
    public static let indentation: [FormatCommand] = [.indent, .outdent]

    public var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .inlineCode: "Inline Code"
        case .codeBlock: "Code Block"
        case .link: "Link"
        case .image: "Image"
        case .heading(let level): "Heading \(level)"
        case .blockquote: "Blockquote"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .indent: "Indent"
        case .outdent: "Outdent"
        }
    }

    /// SF Symbol for toolbar buttons.
    public var symbolName: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .highlight: "highlighter"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "curlybraces"
        case .link: "link"
        case .image: "photo"
        case .heading: "textformat.size"
        case .blockquote: "text.quote"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .taskList: "checklist"
        case .indent: "increase.indent"
        case .outdent: "decrease.indent"
        }
    }

    public var shortcut: KeyboardShortcut {
        switch self {
        case .bold: KeyboardShortcut("b", modifiers: .command)
        case .italic: KeyboardShortcut("i", modifiers: .command)
        case .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift])
        case .highlight: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .inlineCode: KeyboardShortcut("e", modifiers: .command)
        case .codeBlock: KeyboardShortcut("e", modifiers: [.command, .shift])
        case .link: KeyboardShortcut("k", modifiers: .command)
        case .image: KeyboardShortcut("i", modifiers: [.command, .shift])
        case .heading(let level): KeyboardShortcut(KeyEquivalent(Character("\(Swift.min(6, Swift.max(1, level)))")), modifiers: .command)
        case .blockquote: KeyboardShortcut(".", modifiers: [.command, .shift])
        case .bulletList: KeyboardShortcut("8", modifiers: [.command, .shift])
        case .numberedList: KeyboardShortcut("7", modifiers: [.command, .shift])
        case .taskList: KeyboardShortcut("9", modifiers: [.command, .shift])
        case .indent: KeyboardShortcut("]", modifiers: .command)
        case .outdent: KeyboardShortcut("[", modifiers: .command)
        }
    }

    /// The shortcut as menus print it, modifiers in the order macOS uses: ⌃⌥⇧⌘ then the key.
    public var shortcutLabel: String {
        let shortcut = self.shortcut
        var label = ""
        if shortcut.modifiers.contains(.control) { label += "⌃" }
        if shortcut.modifiers.contains(.option) { label += "⌥" }
        if shortcut.modifiers.contains(.shift) { label += "⇧" }
        if shortcut.modifiers.contains(.command) { label += "⌘" }
        return label + String(shortcut.key.character).uppercased()
    }

    /// The edit this command makes to `text` with `selection`, or nil when there is nothing to do.
    public func edit(in text: NSString, selection: NSRange, configuration: EditorConfiguration) -> TextEdit? {
        switch self {
        case .bold: EditTransforms.toggleWrap("**", in: text, selection: selection)
        case .italic: EditTransforms.toggleWrap("*", in: text, selection: selection)
        case .strikethrough: EditTransforms.toggleWrap("~~", in: text, selection: selection)
        case .highlight: EditTransforms.toggleWrap("==", in: text, selection: selection)
        case .inlineCode: EditTransforms.toggleWrap("`", in: text, selection: selection)
        case .codeBlock: EditTransforms.codeBlock(in: text, selection: selection)
        case .link: EditTransforms.insertLink(image: false, in: text, selection: selection)
        case .image: EditTransforms.insertLink(image: true, in: text, selection: selection)
        case .heading(let level): EditTransforms.setHeading(level: level, in: text, selection: selection)
        case .blockquote: EditTransforms.toggleLinePrefix(.blockquote, in: text, selection: selection)
        case .bulletList: EditTransforms.toggleLinePrefix(.bullet, in: text, selection: selection)
        case .numberedList: EditTransforms.toggleLinePrefix(.numbered, in: text, selection: selection)
        case .taskList: EditTransforms.toggleLinePrefix(.task, in: text, selection: selection)
        case .indent: EditTransforms.indent(in: text, selection: selection, unit: configuration.indentUnit, wholeLines: true)
        case .outdent: EditTransforms.outdent(in: text, selection: selection, unit: configuration.indentUnit)
        }
    }
}
