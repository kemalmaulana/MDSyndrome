import Foundation

/// What a click on a link in the preview should do.
public enum LinkAction: Equatable, Sendable {
    /// `http`, `https` and `mailto`: the default app handles it.
    case open(URL)
    /// A `#fragment` inside this document.
    case scroll(fragment: String)
    /// A Markdown file that exists, to open in MDSyndrome.
    case openDocument(URL, fragment: String?)
    /// Another scheme, or a file that is not Markdown: ask before doing anything.
    case confirm(URL)
    /// A link to a file that is not there.
    case missing(URL)
    /// Nothing sensible to do: empty or malformed, `javascript:` / `data:` / `vbscript:`, or a relative path in a
    /// document that has not been saved yet.
    case ignore
}

/// Decides what a click on a preview link does. Documents are untrusted input: a `file:` link to an app or a
/// custom URL scheme must not launch anything, so only web and mail links open without asking (PRD PV-8, NF-8).
public enum LinkPolicy {
    /// The Markdown extensions MDSyndrome opens (PRD DOC-2).
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// - Parameters:
    ///   - baseURL: the folder of the document, which relative links start from; nil for a document that has not been saved.
    ///   - fileExists: how to tell whether a file is there; tests pass their own.
    public static func action(for url: URL, baseURL: URL?, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> LinkAction {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .open(url)
        case "javascript", "data", "vbscript":
            return .ignore
        case "file":
            guard url.host.map({ $0.isEmpty || $0 == "localhost" }) ?? true else { return .ignore }
            return fileAction(for: URL(fileURLWithPath: url.path), fragment: url.fragment, fileExists: fileExists)
        case nil:
            let fragment = url.fragment.flatMap { $0.isEmpty ? nil : $0 }
            let path = url.path
            if path.isEmpty { return fragment.map { .scroll(fragment: $0) } ?? .ignore }
            guard let baseURL else { return .ignore }
            return fileAction(for: URL(fileURLWithPath: path, relativeTo: baseURL), fragment: fragment, fileExists: fileExists)
        default:
            return .confirm(url)
        }
    }

    private static func fileAction(for file: URL, fragment: String?, fileExists: (URL) -> Bool) -> LinkAction {
        let target = file.standardizedFileURL.resolvingSymlinksInPath()
        guard fileExists(target) else { return .missing(target) }
        if markdownExtensions.contains(target.pathExtension.lowercased()) {
            return .openDocument(target, fragment: fragment.flatMap { $0.isEmpty ? nil : $0 })
        }
        return .confirm(target)
    }
}
