import Foundation
import MarkdownCore
import SwiftUI
import WebRenderKit

/// What an export needs that a live view normally fetches while it is on screen: image bytes and the web
/// renderer's pictures. `ImageRenderer` never runs `.task`, so an export prepares all of it first and the
/// views read it synchronously through `\.exportResources`.
public struct ExportResources: Sendable {
    public enum Outcome: Sendable, Equatable {
        case picture(RenderedImage)
        case failed(RenderError)
    }

    public internal(set) var images: [ImageSource: Data] = [:]
    public internal(set) var imageErrors: [ImageSource: String] = [:]
    public internal(set) var pictures: [RenderRequest: Outcome] = [:]
    /// A raw HTML block as written → the block with its images inlined as `data:` URIs.
    public internal(set) var inlinedHTML: [String: String] = [:]
    /// The width in points HTML blocks are laid out at (the PDF's content width).
    public var contentWidth: Double = 700

    public init() {}

    public struct Options: Sendable {
        public var schemes: [ColorScheme]
        public var includeImages: Bool
        public var includeHTMLBlocks: Bool
        public var contentWidth: Double
        public var allowRemoteImages: Bool

        public init(schemes: [ColorScheme], includeImages: Bool, includeHTMLBlocks: Bool, contentWidth: Double, allowRemoteImages: Bool) {
            self.schemes = schemes
            self.includeImages = includeImages
            self.includeHTMLBlocks = includeHTMLBlocks
            self.contentWidth = contentWidth
            self.allowRemoteImages = allowRemoteImages
        }

        /// Light only, on paper: images, diagrams, formulas and HTML blocks.
        public static func pdf(contentWidth: Double, allowRemoteImages: Bool) -> Options {
            Options(schemes: [.light], includeImages: true, includeHTMLBlocks: true, contentWidth: contentWidth, allowRemoteImages: allowRemoteImages)
        }

        /// Light and dark pictures for diagrams and fallback formulas; images stay links.
        public static let html = Options(schemes: [.light, .dark], includeImages: false, includeHTMLBlocks: false, contentWidth: 700, allowRemoteImages: false)
    }

    /// Fetches everything `document` needs. A failure is recorded, never thrown, so one bad diagram does not stop an export. Cancelling
    /// the surrounding task stops early and returns what is ready. A document that needs no web rendering never starts WebKit.
    @MainActor
    public static func prepare(_ document: MarkdownDocument, baseURL: URL?, renderer: (any WebRendering)?, theme: PreviewTheme,
                               options: Options) async -> ExportResources {
        let signpost = Signposts.signposter
        let interval = signpost.beginInterval("export prepare", id: signpost.makeSignpostID())
        defer { signpost.endInterval("export prepare", interval) }

        var result = ExportResources()
        result.contentWidth = options.contentWidth
        let needs = ExportNeeds.collect(document.blocks, theme: theme, contextSizes: options.includeImages)

        if options.includeImages {
            for source in Set(needs.imageSources) {
                if Task.isCancelled { return result }
                let resolved = ImageSource.resolve(source, baseURL: baseURL)
                do {
                    result.images[resolved] = try await ImageLoader.data(for: resolved, allowRemote: options.allowRemoteImages)
                } catch {
                    result.imageErrors[resolved] = error.localizedDescription
                }
            }
        }

        guard let renderer else { return result }
        for scheme in options.schemes {
            for request in needs.requests(theme: theme, scheme: scheme) where result.pictures[request] == nil {
                if Task.isCancelled { return result }
                await result.render(request, with: renderer)
            }
            guard options.includeHTMLBlocks else { continue }
            for html in Set(needs.htmlBlocks) {
                if Task.isCancelled { return result }
                if result.inlinedHTML[html] == nil {
                    result.inlinedHTML[html] = await HTMLImageInliner.inline(html, baseURL: baseURL, allowRemote: options.allowRemoteImages)
                }
                let request = PictureRequests.html(result.inlinedHTML[html] ?? html, width: options.contentWidth, theme: theme, scheme: scheme)
                if result.pictures[request] == nil { await result.render(request, with: renderer) }
            }
        }
        return result
    }

    @MainActor
    private mutating func render(_ request: RenderRequest, with renderer: any WebRendering) async {
        do {
            pictures[request] = .picture(try await renderer.render(request))
        } catch let error as RenderError {
            pictures[request] = .failed(error)
        } catch {
            // Cancelled: leave the request unanswered.
        }
    }
}

extension EnvironmentValues {
    /// Set while a document is drawn for export; nil in the live preview.
    @Entry public var exportResources: ExportResources? = nil
}
