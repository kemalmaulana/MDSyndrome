import Foundation

/// Plans what pasting or dropping images into a document does (PRD ED-11): which files are written or copied, and the
/// Markdown to insert. Pure: it reads nothing but `exists`, so it is tested without a file system.
public enum ImageInsertion {
    public enum Item: Sendable, Equatable {
        /// Image data from the pasteboard, already encoded as PNG.
        case bitmap(Data)
        case file(URL)
    }

    public enum Action: Sendable, Equatable {
        case write(Data, to: URL)
        case copy(from: URL, to: URL)
    }

    public struct Plan: Sendable, Equatable {
        public var actions: [Action]
        public var markdown: String
    }

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "heic", "svg"]

    public static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// - Parameters:
    ///   - imageFolder: a folder name relative to `documentFolder`; empty means `documentFolder` itself.
    ///   - exists: whether a file is already there, so a name is never reused.
    public static func plan(items: [Item], documentFolder: URL, imageFolder: String, now: Date, timeZone: TimeZone = .current,
                            exists: (URL) -> Bool) -> Plan {
        let folder = imageFolder.isEmpty ? documentFolder : documentFolder.appendingPathComponent(imageFolder, isDirectory: true)
        var taken = Set<String>()
        func free(_ name: String) -> URL {
            let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var candidate = name
            var n = 0
            while exists(folder.appendingPathComponent(candidate)) || taken.contains(candidate) {
                n += 1
                candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            }
            taken.insert(candidate)
            return folder.appendingPathComponent(candidate)
        }

        var actions: [Action] = []
        var lines: [String] = []
        for item in items {
            switch item {
            case .bitmap(let data):
                let destination = free("image-\(stamp(now, timeZone)).png")
                actions.append(.write(data, to: destination))
                lines.append("![](\(link(to: destination, from: documentFolder)))")
            case .file(let url):
                // macOS hands back file names decomposed (e + a combining accent); links and copies use the composed form,
                // which is what other systems and Markdown tools expect.
                let name = url.lastPathComponent.precomposedStringWithCanonicalMapping
                let alt = (name as NSString).deletingPathExtension.filter { $0 != "[" && $0 != "]" }
                if let inside = relativePath(of: url, in: documentFolder) {
                    lines.append("![\(alt)](\(encode(inside)))")
                } else {
                    let destination = free(name)
                    actions.append(.copy(from: url, to: destination))
                    lines.append("![\(alt)](\(link(to: destination, from: documentFolder)))")
                }
            }
        }
        return Plan(actions: actions, markdown: lines.joined(separator: "\n"))
    }

    private static func stamp(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// The path of `url` below `folder`, or nil when it is somewhere else.
    private static func relativePath(of url: URL, in folder: URL) -> String? {
        let base = folder.standardizedFileURL.pathComponents, target = url.standardizedFileURL.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }

    private static func link(to destination: URL, from documentFolder: URL) -> String {
        encode(relativePath(of: destination, in: documentFolder) ?? destination.lastPathComponent)
    }

    /// Percent-encodes a relative path for a Markdown link: spaces, non-ASCII letters and parentheses.
    private static func encode(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        let composed = path.precomposedStringWithCanonicalMapping
        return composed.addingPercentEncoding(withAllowedCharacters: allowed) ?? composed
    }
}
