import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Tests that draw offscreen (ImageRenderer) or create windows need an interactive window
    /// server. GitHub's macOS runners hang on them, so they run locally only (`CI` is set on GitHub).
    static var requiresWindowServer: Self {
        .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Needs an interactive window server; runs locally only")
    }
}
