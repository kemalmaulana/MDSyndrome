import AppKit
import Testing
@testable import MDSyndrome

@MainActor
@Suite struct MenuBarTests {
    private struct Entry {
        let shortcut: String
        let title: String
    }

    /// Every key equivalent in the menu bar, with the path of the item that owns it.
    private func entries(in menu: NSMenu, path: [String] = []) -> [Entry] {
        menu.items.flatMap { item -> [Entry] in
            var found: [Entry] = []
            if !item.keyEquivalent.isEmpty, !item.isSeparatorItem {
                let flags = item.keyEquivalentModifierMask.intersection([.command, .option, .shift, .control])
                found.append(Entry(shortcut: "\(flags.rawValue)-\(item.keyEquivalent.lowercased())", title: (path + [item.title]).joined(separator: " > ")))
            }
            if let submenu = item.submenu { found += entries(in: submenu, path: path + [item.title]) }
            return found
        }
    }

    @Test func noTwoMenuItemsShareAShortcut() throws {
        let menu = try #require(NSApp.mainMenu, "the hosted app should have a menu bar")
        let grouped = Dictionary(grouping: entries(in: menu), by: \.shortcut)
        let clashes = grouped.filter { $0.value.count > 1 }.map { "\($0.value.map(\.title))" }
        #expect(clashes.isEmpty, "shared shortcuts: \(clashes)")
    }

    @Test func theFormatMenuHasEveryCommand() throws {
        let menu = try #require(NSApp.mainMenu)
        let format = try #require(menu.items.first { $0.title == "Format" }?.submenu)
        let titles = Set(entries(in: format).map(\.title))
        #expect(titles.contains("Bold"))
        #expect(titles.contains("Heading > Heading 3"))
        #expect(titles.contains("Outdent"))
    }

    @Test func theEditMenuHasFindWithTheStandardShortcuts() throws {
        let menu = try #require(NSApp.mainMenu)
        let edit = try #require(menu.items.first { $0.title == "Edit" }?.submenu)
        let find = try #require(edit.items.first { $0.title == "Find" }?.submenu)
        let byTitle = Dictionary(uniqueKeysWithValues: find.items.map { ($0.title, $0.keyEquivalent) })
        #expect(byTitle["Find…"] == "f")
        #expect(byTitle["Find Next"] == "g")
        #expect(byTitle["Find Previous"] == "g")
        #expect(byTitle["Find and Replace…"] == "f")
        #expect(byTitle["Jump to Selection"] == "j")
    }
}
