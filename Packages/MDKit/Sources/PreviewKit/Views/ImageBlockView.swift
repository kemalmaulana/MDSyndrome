import AppKit
import SwiftUI

struct ImageBlockView: View {
    let source: String
    let alt: String
    /// Display width from HTML `<img width>`; otherwise the image's own width (never upscaled).
    var width: Double? = nil
    @Environment(\.documentBaseURL) private var baseURL
    @Environment(\.previewTheme) private var theme
    @Environment(\.previewReloadToken) private var reloadToken
    @Environment(\.loadRemoteImages) private var loadRemoteImages
    @Environment(\.exportResources) private var export
    @State private var phase: Phase = .loading

    /// What a load depends on: the file or URL, and a reload request.
    private struct LoadKey: Hashable {
        let source: ImageSource
        let reloadToken: Int
        let allowRemote: Bool
    }

    enum Phase {
        case loading
        case loaded(NSImage)
        case failed(String)
    }

    var body: some View {
        let resolved = ImageSource.resolve(source, baseURL: baseURL)
        if let export {
            content(for: exportPhase(resolved, export))
        } else {
            content(for: phase)
                .task(id: LoadKey(source: resolved, reloadToken: reloadToken, allowRemote: loadRemoteImages)) {
                    phase = .loading
                    do {
                        let data = try await ImageLoader.data(for: resolved, reload: reloadToken > 0, allowRemote: loadRemoteImages)
                        phase = NSImage(data: data).map(Phase.loaded) ?? .failed("Unsupported image format")
                    } catch {
                        phase = .failed(error.localizedDescription)
                    }
                }
        }
    }

    @ViewBuilder
    private func content(for phase: Phase) -> some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.small).frame(height: 40)
        case .loaded(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: width ?? image.size.width)
                .accessibilityLabel(alt)
        case .failed(let reason):
            Label(alt.isEmpty ? reason : alt, systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(theme.secondaryText.color)
                .help(reason)
        }
    }

    /// An export draws what was prepared for it: bytes already read, or the reason they could not be.
    private func exportPhase(_ source: ImageSource, _ export: ExportResources) -> Phase {
        if let data = export.images[source] { return NSImage(data: data).map(Phase.loaded) ?? .failed("Unsupported image format") }
        return .failed(export.imageErrors[source] ?? "The image was not loaded")
    }
}
