import Foundation

/// The snapshot web view may not read files or the network, so the pictures an HTML block refers to are
/// read here and handed over inside the HTML as `data:` URIs.
enum HTMLImageInliner {
    static let maxImages = 12
    static let maxBytesPerImage = 4 * 1_024 * 1_024

    // <img … src="value"> or src='value'; group 2 or 3 is the value.
    private static let imageSource = try! NSRegularExpression(pattern: #"(<img\b[^>]*?\bsrc\s*=\s*)(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])

    static func inline(_ html: String, baseURL: URL?, reload: Bool = false, allowRemote: Bool = true) async -> String {
        let text = html as NSString
        let matches = imageSource.matches(in: html, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return html }

        func value(of match: NSTextCheckingResult) -> NSRange {
            match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        }
        var sources: [String] = []
        for match in matches {
            let source = text.substring(with: value(of: match))
            if !source.hasPrefix("data:"), !sources.contains(source) { sources.append(source) }
        }

        var dataURIs: [String: String] = [:]
        for source in sources.prefix(maxImages) {
            let resolved = ImageSource.resolve(source, baseURL: baseURL)
            guard let data = try? await ImageLoader.data(for: resolved, reload: reload, allowRemote: allowRemote), data.count <= maxBytesPerImage,
                  let mime = mimeType(of: data) else { continue }
            dataURIs[source] = "data:\(mime);base64,\(data.base64EncodedString())"
        }
        guard !dataURIs.isEmpty else { return html }

        var result = html as NSString
        for match in matches.reversed() {
            let range = value(of: match)
            if let uri = dataURIs[text.substring(with: range)] {
                result = result.replacingCharacters(in: range, with: uri) as NSString
            }
        }
        return result as String
    }

    /// The image type from the first bytes, since a file name or a server header can lie. nil for anything
    /// that is not a picture format a web view draws.
    static func mimeType(of data: Data) -> String? {
        let head = [UInt8](data.prefix(16))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if head.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if head.starts(with: Array("RIFF".utf8)), head.count >= 12, Array(head[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        if head.starts(with: Array("BM".utf8)) { return "image/bmp" }
        if let text = String(data: data.prefix(1_024), encoding: .utf8), text.contains("<svg") { return "image/svg+xml" }
        return nil
    }
}
