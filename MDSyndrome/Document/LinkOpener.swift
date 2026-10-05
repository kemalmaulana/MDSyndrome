import AppKit
import PreviewKit
import UniformTypeIdentifiers

/// Carries out the links that leave the preview: another Markdown document, another file, another scheme. Web
/// and mail links and `#fragment` links never get here, the preview handles those. A document is untrusted, so
/// nothing but a Markdown file opens without asking, and a program is never run from a link, only shown in Finder.
@MainActor
enum LinkOpener {
    /// Asks before following a link. `isProgram` means the link points at an app or a script.
    typealias Confirmation = @MainActor (_ url: URL, _ isProgram: Bool, _ window: NSWindow?, _ answer: @escaping @MainActor (Bool) -> Void) -> Void

    /// What actually happens, so tests can watch it.
    struct Effects {
        var openDocument: @MainActor (URL) -> Void = { url in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        var open: @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
        var reveal: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        var beep: @MainActor () -> Void = { NSSound.beep() }
    }

    static func handle(_ action: LinkAction, window: NSWindow?, effects: Effects = Effects(), confirm: Confirmation = askBeforeFollowing) {
        switch action {
        case .open(let url):
            effects.open(url)
        case .scroll, .ignore:
            break
        case .openDocument(let url, _):
            effects.openDocument(url)
        case .missing:
            effects.beep()
        case .confirm(let url):
            let program = isProgram(url)
            confirm(url, program, window) { allowed in
                guard allowed else { return }
                if program { effects.reveal(url) } else { effects.open(url) }
            }
        }
    }

    // MARK: Programs

    /// Extensions that run or install something when opened, whatever the system thinks the type is.
    private static let programExtensions: Set<String> = ["app", "command", "tool", "pkg", "mpkg", "dmg", "jar", "workflow", "action", "scpt", "scptd", "terminal"]

    /// True for a file that would run code if opened: an application, a script, an executable, an installer.
    static func isProgram(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if programExtensions.contains(url.pathExtension.lowercased()) { return true }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        if let type = values?.contentType, type.conforms(to: .application) || type.conforms(to: .executable) || type.conforms(to: .script) {
            return true
        }
        let isDirectory = values?.isDirectory ?? false
        return !isDirectory && FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: Asking

    /// A sheet on the document's window. Cancel is the default button: a click in a document must not be enough.
    static let askBeforeFollowing: Confirmation = { url, isProgram, window, answer in
        let alert = NSAlert()
        let shown = displayText(for: url)
        if isProgram {
            alert.messageText = "This link points to a program"
            alert.informativeText = "\(shown)\n\nMDSyndrome never runs a program from a document. It can show it in Finder."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Show in Finder")
        } else {
            alert.messageText = "Open this link?"
            alert.informativeText = shown
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Open")
        }
        if let window {
            alert.beginSheetModal(for: window) { response in answer(response == .alertSecondButtonReturn) }
        } else {
            answer(alert.runModal() == .alertSecondButtonReturn)
        }
    }

    /// The link as the person should read it: a file's path, anything else as written, cut in the middle past 300 characters.
    static func displayText(for url: URL) -> String {
        let text = url.isFileURL ? url.path : url.absoluteString
        guard text.count > 300 else { return text }
        return String(text.prefix(150)) + "…" + String(text.suffix(149))
    }
}
