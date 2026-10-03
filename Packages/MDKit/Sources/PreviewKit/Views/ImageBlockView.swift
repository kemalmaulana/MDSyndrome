import AppKit
import SwiftUI

struct ImageBlockView: View {
    let source: String
    let alt: String
    @Environment(\.documentBaseURL) private var baseURL
    @Environment(\.previewTheme) private var theme
    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case loaded(NSImage)
        case failed(String)
    }

    var body: some View {
        let resolved = ImageSource.resolve(source, baseURL: baseURL)
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.small).frame(height: 40)
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width)
                    .accessibilityLabel(alt)
            case .failed(let reason):
                Label(alt.isEmpty ? reason : alt, systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(theme.secondaryText.color)
                    .help(reason)
            }
        }
        .task(id: resolved) {
            phase = .loading
            do {
                let data = try await ImageLoader.data(for: resolved)
                phase = NSImage(data: data).map(Phase.loaded) ?? .failed("Unsupported image format")
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
