import AppKit
import Foundation
import Testing
@testable import MDSyndrome

extension Trait where Self == ConditionTrait {
    /// These read the live menu bar of the hosted app. The CI runner's GUI session is not something
    /// they have been checked against, and a hang there costs a quarter of an hour, so they run locally
    /// (`make test`) only.
    static var notOnCI: Self {
        .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Reads the live menu bar; runs locally only")
    }
}

@MainActor
@Suite(.notOnCI) struct MenuBarTests {
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

    /// SwiftUI builds the menu bar after launch; give it a moment before reading it.
    private func menuBar() async throws -> NSMenu {
        for _ in 0..<50 {
            if let menu = NSApp.mainMenu, menu.items.contains(where: { $0.title == "Format" }) { return menu }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try #require(NSApp.mainMenu, "the hosted app should have a menu bar")
    }

    @Test func noTwoMenuItemsShareAShortcut() async throws {
        let menu = try await menuBar()
        let grouped = Dictionary(grouping: entries(in: menu), by: \.shortcut)
        let clashes = grouped.filter { $0.value.count > 1 }.map { "\($0.value.map(\.title))" }
        #expect(clashes.isEmpty, "shared shortcuts: \(clashes)")
    }

    @Test func theFormatMenuHasEveryCommand() async throws {
        let menu = try await menuBar()
        let format = try #require(menu.items.first { $0.title == "Format" }?.submenu)
        let titles = Set(entries(in: format).map(\.title))
        #expect(titles.contains("Bold"))
        #expect(titles.contains("Heading > Heading 3"))
        #expect(titles.contains("Outdent"))
    }

    @Test func theEditMenuHasFindWithTheStandardShortcuts() async throws {
        let menu = try await menuBar()
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
