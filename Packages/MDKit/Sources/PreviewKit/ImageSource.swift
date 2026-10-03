import Foundation

/// Where an image in the document comes from.
public enum ImageSource: Hashable, Sendable {
    case local(URL)
    case remote(URL)
    case unresolved(reason: String)

    public static func resolve(_ source: String, baseURL: URL?) -> ImageSource {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unresolved(reason: "Empty image path") }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme.count > 1 {
            switch scheme {
            case "http", "https": return .remote(url)
            case "file": return .local(url)
            default: return .unresolved(reason: "Unsupported image URL scheme “\(scheme)”")
            }
        }
        let path = trimmed.removingPercentEncoding ?? trimmed
        if path.hasPrefix("/") { return .local(URL(fileURLWithPath: path)) }
        if path.hasPrefix("~") { return .local(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)) }
        guard let baseURL else { return .unresolved(reason: "Save the document to show relative images") }
        return .local(URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL)
    }
}

public enum ImageLoadError: LocalizedError, Equatable {
    case unresolved(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unresolved(let reason): reason
        case .http(let status): "Server returned HTTP \(status)"
        }
    }
}

public enum ImageLoader {
    /// Reads image bytes off the main actor. Remote loads go through
    /// `URLSession.shared`, whose `URLCache` gives memory + disk caching.
    public static func data(for source: ImageSource) async throws -> Data {
        switch source {
        case .local(let url):
            return try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        case .remote(let url):
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImageLoadError.http(http.statusCode)
            }
            return data
        case .unresolved(let reason):
            throw ImageLoadError.unresolved(reason)
        }
    }
}
