import AppKit
import Foundation
import SwiftUI
import Testing
@testable import EditorKit

private let folder = URL(fileURLWithPath: "/tmp/doc", isDirectory: true)
private let utc = TimeZone(identifier: "UTC")!
private let moment = ISO8601DateFormatter().date(from: "2026-10-09T10:30:05Z")!
private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private func plan(_ items: [ImageInsertion.Item], imageFolder: String = "assets", exists: @escaping (URL) -> Bool = { _ in false }) -> ImageInsertion.Plan {
    ImageInsertion.plan(items: items, documentFolder: folder, imageFolder: imageFolder, now: moment, timeZone: utc, exists: exists)
}

/// The destinations of a plan, as paths, so the comparison does not depend on how a URL was built.
private func destinations(_ plan: ImageInsertion.Plan) -> [String] {
    plan.actions.map { action in
        switch action {
        case .write(_, let url): "write " + url.path
        case .copy(let from, let to): "copy \(from.path) -> \(to.path)"
        }
    }
}

@Suite struct ImageInsertionPlanTests {
    @Test func aPastedPictureIsSavedUnderATimestampedName() {
        let result = plan([.bitmap(png)])
        #expect(destinations(result) == ["write /tmp/doc/assets/image-20261009-103005.png"])
        #expect(result.markdown == "![](assets/image-20261009-103005.png)")
    }

    @Test func twoPicturesInTheSameSecondDoNotShareAName() {
        let result = plan([.bitmap(png), .bitmap(png)])
        #expect(destinations(result) == ["write /tmp/doc/assets/image-20261009-103005.png", "write /tmp/doc/assets/image-20261009-103005-1.png"])
        #expect(result.markdown == "![](assets/image-20261009-103005.png)\n![](assets/image-20261009-103005-1.png)")
    }

    @Test func aNameThatAlreadyExistsGetsASuffix() {
        let result = plan([.bitmap(png)], exists: { $0.lastPathComponent == "image-20261009-103005.png" })
        #expect(destinations(result) == ["write /tmp/doc/assets/image-20261009-103005-1.png"])
    }

    @Test func aDroppedFileFromElsewhereIsCopiedAndLinkedWithAnEncodedPath() {
        let source = URL(fileURLWithPath: "/Users/x/Pictures/My Photo (1).png")
        let result = plan([.file(source)])
        #expect(destinations(result) == ["copy /Users/x/Pictures/My Photo (1).png -> /tmp/doc/assets/My Photo (1).png"])
        #expect(result.markdown == "![My Photo (1)](assets/My%20Photo%20%281%29.png)")
    }

    @Test func aDroppedFileAlreadyBesideTheDocumentIsOnlyLinked() {
        let result = plan([.file(URL(fileURLWithPath: "/tmp/doc/img/a.png"))])
        #expect(result.actions.isEmpty)
        #expect(result.markdown == "![a](img/a.png)")
    }

    @Test func nonASCIINamesAreEncoded() {
        let result = plan([.file(URL(fileURLWithPath: "/Users/x/Café.png"))])
        #expect(result.markdown == "![Café](assets/Caf%C3%A9.png)")
    }

    @Test func bracketsInAFileNameAreDroppedFromTheAltText() {
        let result = plan([.file(URL(fileURLWithPath: "/Users/x/a[1].png"))])
        #expect(result.markdown.hasPrefix("![a1]("))
    }

    @Test func anEmptyFolderNameMeansTheDocumentsOwnFolder() {
        let result = plan([.bitmap(png)], imageFolder: "")
        #expect(destinations(result) == ["write /tmp/doc/image-20261009-103005.png"])
        #expect(result.markdown == "![](image-20261009-103005.png)")
    }

    @Test func aCollisionWithAnExistingFileInTheDocumentFolderGetsASuffix() {
        let result = plan([.file(URL(fileURLWithPath: "/Users/x/a.png"))], exists: { $0.lastPathComponent == "a.png" })
        #expect(destinations(result) == ["copy /Users/x/a.png -> /tmp/doc/assets/a-1.png"])
    }

    @Test func onlyPictureFilesCount() {
        #expect(ImageInsertion.isImageFile(URL(fileURLWithPath: "/a/b.PNG")))
        #expect(ImageInsertion.isImageFile(URL(fileURLWithPath: "/a/b.jpeg")))
        #expect(!ImageInsertion.isImageFile(URL(fileURLWithPath: "/a/b.md")))
        #expect(!ImageInsertion.isImageFile(URL(fileURLWithPath: "/a/b")))
    }
}

/// The real text view with a throwaway document folder and named pasteboards, so the user's clipboard is never touched.
@MainActor
@Suite(.serialized) struct ImagePasteTests {
    private let controller = EditorController()
    private let textView: MarkdownTextView
    private let coordinator: EditorCoordinator
    private let scrollView: NSScrollView
    private let folder: URL

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        coordinator = EditorCoordinator(text: .constant(""))
        (scrollView, textView) = MarkdownEditorView.makeViews()
        coordinator.attach(to: textView, scrollView: scrollView, theme: .tomorrowPlus, configuration: .macDownDefaults, controller: controller)
        coordinator.setText("before after")
    }

    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("mds-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func aPictureOnTheClipboardIsSavedAndLinked() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        controller.documentFolder = folder
        let board = pasteboard()
        board.setData(png, forType: .png)
        let items = try #require(textView.imageItems(on: board))
        textView.insertImages(items, at: 7)
        let text = textView.string
        #expect(text.hasPrefix("before ![](assets/image-") && text.hasSuffix(".png)after"))
        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("assets").path)
        #expect(saved.count == 1 && saved[0].hasPrefix("image-") && saved[0].hasSuffix(".png"))
    }

    @Test func aDocumentWithoutAFileWritesNothingAndAsksToBeSaved() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        controller.documentFolder = nil
        var asked = 0
        controller.onImageNeedsSavedDocument = { asked += 1 }
        let board = pasteboard()
        board.setData(png, forType: .png)
        textView.insertImages(try #require(textView.imageItems(on: board)), at: 0)
        #expect(asked == 1)
        #expect(textView.string == "before after")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("assets").path))
    }

    @Test func textAlongsideAPictureWins() {
        let board = pasteboard()
        board.setString("copied text", forType: .string)
        board.setData(png, forType: .png)
        #expect(textView.imageItems(on: board) == nil, "a web page puts both on the clipboard; the text is what the person copied")
    }

    @Test func filesThatAreNotAllPicturesAreLeftToTheDefaultPaste() {
        let board = pasteboard()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.png") as NSURL, URL(fileURLWithPath: "/tmp/notes.md") as NSURL])
        #expect(textView.imageItems(on: board) == nil)
    }

    @Test func pictureFilesAreTakenAsFiles() throws {
        let board = pasteboard()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.png") as NSURL])
        #expect(try #require(textView.imageItems(on: board)) == [.file(URL(fileURLWithPath: "/tmp/a.png"))])
    }

    @Test func theInsertionIsOneUndoStep() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        controller.documentFolder = folder
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        let board = pasteboard()
        board.setData(png, forType: .png)
        textView.insertImages(try #require(textView.imageItems(on: board)), at: 0)
        #expect(textView.string.hasPrefix("![]("))
        textView.undoManager?.undo()
        #expect(textView.string == "before after")
    }
}
