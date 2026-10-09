import AppKit
import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI
import WebRenderKit

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?
    let webRenderer: WebRenderer

    @State private var session = DocumentSession()
    @State private var editor = EditorController()
    /// Bumped by ⌘R so the preview reads its images from disk again.
    @State private var previewReloadToken = 0
    @State private var previewSearch = PreviewSearch()
    @State private var previewScroller = PreviewScroller()
    /// Keeps the two panes at the same place in the document.
    @State private var sync = SyncScrollCoordinator()
    @State private var model = SettingsModel.shared
    /// The outline column (⌃⌘S); closed until the person opens it.
    @SceneStorage("outlineVisible") private var outlineVisible = false
    /// The heading the document is at, for the outline's highlight.
    @State private var currentHeading: BlockID?
    /// Where Find goes in the split layout: the pane the user clicked or typed in last.
    @State private var activePane: Pane = .editor
    @SceneStorage("layoutMode") private var layoutMode: LayoutMode = .split
    @SceneStorage("splitRatio") private var splitRatio: Double = 0.5

    init(document: Binding<MarkdownFileDocument>, fileURL: URL?, webRenderer: WebRenderer) {
        _document = document
        self.fileURL = fileURL
        self.webRenderer = webRenderer
        // A new window opens in the layout the General settings ask for; later it remembers its own.
        let openInPreview = UserDefaults.standard.bool(forKey: SettingsKey.openInPreview)
        _layoutMode = SceneStorage(wrappedValue: openInPreview ? .preview : .split, "layoutMode")
    }

    private var editorIsVisible: Bool { layoutMode != .preview }
    private static let outlineWidth: Double = 220

    var body: some View {
        lifecycle
            .onChange(of: model.settings.syncScroll) { _, enabled in sync.isEnabled = enabled }
            .onChange(of: model.settings.markdown) { _, options in
                session.options = options
                session.textDidChange(document.text)
            }
            .onChange(of: layoutMode, initial: true) { _, mode in
                sync.layoutDidChange(editorVisible: mode != .preview, previewVisible: mode != .editor)
            }
            .onChange(of: session.renderCount, initial: true) { _, _ in sync.renderDidChange(session.rendered.sourceMap) }
            .onChange(of: previewSearch.isPresented) { _, isPresented in if isPresented { activePane = .preview } }
            .onChange(of: layoutMode) { _, mode in if mode == .editor { previewSearch.close() } }
            .onChange(of: document.text) { _, newText in session.textDidChange(newText) }
    }

    private var panes: some View {
        HStack(spacing: 0) {
            if outlineVisible {
                OutlineSidebar(items: session.rendered.outline, current: currentHeading, select: { sync.navigate(to: $0.id) })
                    .frame(width: Self.outlineWidth)
                Divider()
            }
            VStack(spacing: 0) {
                PaneLayout(mode: layoutMode, ratio: $splitRatio) {
                    MarkdownEditorView(text: $document.text, theme: model.editorTheme(named: model.settings.editorThemeName),
                                       configuration: model.settings.editor, isHidden: !editorIsVisible, controller: editor)
                } preview: {
                    MarkdownPreview(rendered: session.rendered, baseURL: fileURL?.deletingLastPathComponent(), theme: model.previewTheme, reloadToken: previewReloadToken,
                                    search: layoutMode == .editor ? nil : previewSearch, webRenderer: webRenderer, scroller: previewScroller,
                                    linkHandler: { LinkOpener.handle($0, window: NSApp.keyWindow) }, onToggleTask: toggleTask, loadRemoteImages: model.settings.loadRemoteImages)
                        .simultaneousGesture(TapGesture().onEnded { activePane = .preview })
                }
                Divider()
                StatusBar(stats: session.rendered.stats)
            }
            .frame(minWidth: 600)
        }
        .frame(minHeight: 400)
        .background(WindowZoomBehavior())
    }

    private var focused: some View {
        panes
        .toolbar(id: "document") {
            DocumentToolbar(layoutMode: $layoutMode, outlineVisible: $outlineVisible, editor: editor, editorIsVisible: editorIsVisible, export: exportActions)
        }
        .focusedSceneValue(\.layoutMode, $layoutMode)
        .focusedSceneValue(\.exportActions, exportActions)
        .focusedSceneValue(\.outlineVisible, $outlineVisible)
        .focusedSceneValue(\.editorController, editorIsVisible ? editor : nil)
        .focusedSceneValue(\.findRouter, FindRouter(editor: editorIsVisible ? editor : nil, preview: layoutMode == .editor ? nil : previewSearch,
                                                   layout: layoutMode, pane: activePane))
        .focusedSceneValue(\.reloadDocument, fileURL == nil ? nil : DocumentAction(run: reloadFromDisk))
    }

    private var lifecycle: some View {
        focused
        .onAppear {
            let pane = $activePane
            let sync = sync
            editor.onFocus = {
                if pane.wrappedValue != .editor { pane.wrappedValue = .editor }
                sync.editorActivity()
            }
            sync.attach(editor: editor, preview: previewScroller)
            sync.isEnabled = model.settings.syncScroll
            sync.onPosition = { line in
                let heading = Outline.current(in: session.rendered.outline, atLine: line)?.id
                if heading != currentHeading { currentHeading = heading }
            }
            previewScroller.onNavigate = { [weak sync] id in sync?.previewDidNavigate(to: id) }
        }
        .task {
            session.options = model.settings.markdown
            await session.renderNow(document.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in pullChangesFromDisk() }
        .modifier(EditorDocumentFolder(editor: editor, fileURL: fileURL))
    }

    /// What gets exported: the current render, on the theme chosen in Settings at normal size.
    private var exportSource: ExportService.Source {
        let name = model.settings.previewThemeName
        let theme = model.previewThemes.first { $0.name == name } ?? .github
        return ExportService.Source(document: session.rendered.document, title: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled",
                                    baseURL: fileURL?.deletingLastPathComponent(), theme: theme,
                                    renderer: webRenderer, allowRemoteImages: model.settings.loadRemoteImages)
    }

    private var exportActions: ExportActions {
        ExportActions(
            exportHTML: DocumentAction { ExportService.exportHTML(exportSource, window: NSApp.keyWindow) },
            exportPDF: DocumentAction { ExportService.exportPDF(exportSource, window: NSApp.keyWindow) },
            copyHTML: DocumentAction { ExportService.copyHTML(exportSource) },
            printDocument: DocumentAction { ExportService.printDocument(exportSource, window: NSApp.keyWindow) })
    }

    /// A click on a task checkbox in the preview. The line number belongs to the render the preview shows, so it
    /// is only used while that render is the latest (an edit still waiting for its render would have moved lines);
    /// the editor then refuses a line that holds no task marker.
    private func toggleTask(atLine line: Int) {
        guard session.isCurrent, editor.toggleTask(atLine: line) else {
            NSSound.beep()
            return
        }
    }

    /// Back from another app: if it saved this file meanwhile, show the new text.
    private func pullChangesFromDisk() {
        guard let fileURL, let nsDocument = NSDocumentController.shared.document(for: fileURL) else { return }
        DocumentReloader.reloadIfChangedOnDisk(nsDocument, completion: { reloaded in
            if reloaded { previewReloadToken += 1 }
        })
    }

    /// ⌘R: read the file again and refresh what the preview shows from disk. The text itself reaches the
    /// editor and the preview through the document binding, like any other change.
    private func reloadFromDisk() {
        guard let fileURL, let nsDocument = NSDocumentController.shared.document(for: fileURL) else {
            NSSound.beep()
            return
        }
        DocumentReloader.reload(nsDocument, completion: { reloaded in
            if reloaded { previewReloadToken += 1 }
        })
    }
}

/// Keeps the editor told where the document lives, and what to say when an image arrives before it is saved.
private struct EditorDocumentFolder: ViewModifier {
    let editor: EditorController
    let fileURL: URL?

    func body(content: Content) -> some View {
        content
            .task(id: fileURL) {
                editor.documentFolder = fileURL?.deletingLastPathComponent()
                editor.onImageNeedsSavedDocument = {
                    let alert = NSAlert()
                    alert.messageText = "Save the document first"
                    alert.informativeText = "Pasted and dropped images are saved next to the document, which has no file yet."
                    if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
                }
            }
    }
}
