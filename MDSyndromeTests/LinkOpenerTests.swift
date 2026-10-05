import AppKit
import Foundation
import PreviewKit
import Testing
@testable import MDSyndrome

@MainActor
@Suite struct LinkOpenerTests {
    @MainActor private final class Effects {
        var openedDocuments: [URL] = []
        var opened: [URL] = []
        var revealed: [URL] = []
        var beeps = 0
        var asked: [(url: URL, isProgram: Bool)] = []

        var effects: LinkOpener.Effects {
            LinkOpener.Effects(openDocument: { [self] in openedDocuments.append($0) }, open: { [self] in opened.append($0) },
                               reveal: { [self] in revealed.append($0) }, beep: { [self] in beeps += 1 })
        }

        func confirm(_ answer: Bool) -> LinkOpener.Confirmation {
            { [self] url, isProgram, _, reply in
                asked.append((url, isProgram))
                reply(answer)
            }
        }
    }

    /// A folder with a few files in it, removed afterwards.
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mds-links-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func make(_ name: String, in folder: URL, contents: String = "x", executable: Bool = false, directory: Bool = false) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: directory)
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data(contents.utf8).write(to: url)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        return url
    }

    @Test func aMarkdownDocumentOpensInTheApp() {
        let recorder = Effects()
        let url = URL(fileURLWithPath: "/tmp/other.md")
        LinkOpener.handle(.openDocument(url, fragment: "x"), window: nil, effects: recorder.effects, confirm: recorder.confirm(false))
        #expect(recorder.openedDocuments == [url])
        #expect(recorder.asked.isEmpty)
    }

    @Test func aMissingFileBeepsAndOpensNothing() {
        let recorder = Effects()
        LinkOpener.handle(.missing(URL(fileURLWithPath: "/nope.md")), window: nil, effects: recorder.effects, confirm: recorder.confirm(true))
        #expect(recorder.beeps == 1)
        #expect(recorder.openedDocuments.isEmpty && recorder.opened.isEmpty && recorder.revealed.isEmpty)
    }

    @Test func anchorsAndIgnoredLinksDoNothingHere() {
        let recorder = Effects()
        LinkOpener.handle(.scroll(fragment: "x"), window: nil, effects: recorder.effects, confirm: recorder.confirm(true))
        LinkOpener.handle(.ignore, window: nil, effects: recorder.effects, confirm: recorder.confirm(true))
        #expect(recorder.asked.isEmpty && recorder.opened.isEmpty && recorder.beeps == 0)
    }

    @Test func anotherSchemeOpensOnlyAfterAYes() {
        let url = URL(string: "tel:+123")!
        let no = Effects()
        LinkOpener.handle(.confirm(url), window: nil, effects: no.effects, confirm: no.confirm(false))
        #expect(no.asked.count == 1 && no.asked[0].isProgram == false)
        #expect(no.opened.isEmpty)
        let yes = Effects()
        LinkOpener.handle(.confirm(url), window: nil, effects: yes.effects, confirm: yes.confirm(true))
        #expect(yes.opened == [url])
        #expect(yes.revealed.isEmpty)
    }

    @Test func aProgramIsShownInFinderNeverOpenedEvenAfterAYes() throws {
        try withFolder { folder in
            let programs = [
                try make("Thing.app", in: folder, directory: true), try make("run.command", in: folder), try make("tool", in: folder, contents: "#!/bin/sh\necho hi", executable: true),
                try make("Installer.pkg", in: folder), try make("disk.dmg", in: folder), try make("flow.workflow", in: folder, directory: true), try make("script.scpt", in: folder),
                try make("RUN.COMMAND", in: folder), try make("Tool.jar", in: folder),
            ]
            for program in programs {
                let recorder = Effects()
                LinkOpener.handle(.confirm(program), window: nil, effects: recorder.effects, confirm: recorder.confirm(true))
                #expect(recorder.asked.first?.isProgram == true, "\(program.lastPathComponent) should count as a program")
                #expect(recorder.opened.isEmpty, "\(program.lastPathComponent) must not be opened")
                #expect(recorder.revealed == [program])
            }
        }
    }

    @Test func aProgramThatIsDeclinedIsNeitherOpenedNorShown() throws {
        try withFolder { folder in
            let app = try make("Thing.app", in: folder, directory: true)
            let recorder = Effects()
            LinkOpener.handle(.confirm(app), window: nil, effects: recorder.effects, confirm: recorder.confirm(false))
            #expect(recorder.opened.isEmpty && recorder.revealed.isEmpty)
        }
    }

    @Test func plainFilesAndFoldersAreNotPrograms() throws {
        try withFolder { folder in
            let plain = [try make("notes.txt", in: folder), try make("photo.png", in: folder), try make("docs", in: folder, directory: true),
                         try make("README", in: folder, contents: "text")]
            for url in plain { #expect(!LinkOpener.isProgram(url), "\(url.lastPathComponent)") }
            #expect(!LinkOpener.isProgram(URL(string: "tel:123")!))
            #expect(!LinkOpener.isProgram(URL(string: "https://example.com/run.command")!))
            #expect(!LinkOpener.isProgram(folder.appendingPathComponent("does-not-exist.txt")))
        }
    }

    @Test func aMissingFileWithAProgramNameStillCountsAsAProgram() {
        #expect(LinkOpener.isProgram(URL(fileURLWithPath: "/nowhere/Thing.app")))
        #expect(LinkOpener.isProgram(URL(fileURLWithPath: "/nowhere/x.command")))
    }

    @Test func theLinkIsShownAsAPathOrAsWrittenAndCutInTheMiddleWhenHuge() {
        #expect(LinkOpener.displayText(for: URL(fileURLWithPath: "/Users/me/a b.txt")) == "/Users/me/a b.txt")
        #expect(LinkOpener.displayText(for: URL(string: "tel:+123")!) == "tel:+123")
        let long = URL(string: "custom://" + String(repeating: "a", count: 5_000) + "/end")!
        let shown = LinkOpener.displayText(for: long)
        #expect(shown.count <= 301)
        #expect(shown.hasPrefix("custom://") && shown.hasSuffix("/end") && shown.contains("…"))
    }
}
