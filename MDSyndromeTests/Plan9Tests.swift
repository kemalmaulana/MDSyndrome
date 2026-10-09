import EditorKit
import Foundation
import MarkdownCore
import Testing
@testable import MDSyndrome

@Suite struct ImageFolderSettingTests {
    @Test func defaultsToAssets() {
        #expect(AppSettings.imageFolder(nil) == "assets")
        #expect(AppSettings().editor.imageFolder == "assets")
    }

    @Test func aSingleFolderNameIsKeptAndTrimmed() {
        #expect(AppSettings.imageFolder("  figures ") == "figures")
        #expect(AppSettings.imageFolder("My Images") == "My Images")
    }

    @Test func anEmptyNameMeansTheDocumentsOwnFolder() {
        #expect(AppSettings.imageFolder("") == "")
        #expect(AppSettings.imageFolder("   ") == "")
    }

    @Test(arguments: ["../x", "a/b", ".hidden", "..", "a\\b", "/etc"])
    func namesThatCouldLeaveTheDocumentsFolderFallBackToAssets(name: String) {
        #expect(AppSettings.imageFolder(name) == "assets")
    }

    @Test func theSettingReachesTheEditorConfiguration() {
        let name = "mds-plan9-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("pictures", forKey: SettingsKey.editorImageFolder)
        #expect(AppSettings(defaults: defaults).editor.imageFolder == "pictures")
    }
}

@Suite struct OutlineWidthTests {
    @Test func theWidthStaysWithinTheLimits() {
        #expect(OutlineWidth.clamped(100) == OutlineWidth.range.lowerBound)
        #expect(OutlineWidth.clamped(900) == OutlineWidth.range.upperBound)
        #expect(OutlineWidth.clamped(250) == 250)
        #expect(OutlineWidth.range.contains(OutlineWidth.standard))
    }
}

@MainActor
@Suite struct AdaptiveDebounceTests {
    @Test func aQuickParseIsShownLongBeforeTheFullDebounce() async throws {
        let session = DocumentSession(debounce: .seconds(5))
        await session.renderNow("# a")
        session.textDidChange("# b")
        try await Task.sleep(for: .milliseconds(700))
        #expect(session.isCurrent, "the wait follows how fast the last parse was; the 5 s is only the ceiling")
        #expect(session.rendered.outline.map(\.title) == ["b"])
    }

    @Test func aSlowParseWaitsLongerSoTypingDoesNotKeepTheParserBusy() async throws {
        let session = DocumentSession(debounce: .seconds(5)) { text, options in
            if text == "slow" { Thread.sleep(forTimeInterval: 0.4) }   // about 100 ms of wait afterwards
            return MarkdownPipeline.render(text, options: options)
        }
        await session.renderNow("slow")
        session.textDidChange("next")
        try await Task.sleep(for: .milliseconds(30))
        #expect(!session.isCurrent, "after a 400 ms parse the session waits about 100 ms before the next one")
        try await Task.sleep(for: .milliseconds(700))
        #expect(session.isCurrent)
    }
}
