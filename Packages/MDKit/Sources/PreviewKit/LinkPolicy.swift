import Foundation

/// Decides what a click on a preview link does. Documents are untrusted input:
/// a `file:` link to an app or a custom URL scheme must not launch anything.
/// Until the confirmation prompt (PRD PV-8) lands, only web and mail links open.
public enum LinkPolicy {
    public enum Decision: Equatable, Sendable {
        case openExternally
        case ignore
    }

    public static func decision(for url: URL) -> Decision {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto": .openExternally
        default: .ignore
        }
    }
}
