import Foundation

extension Duration {
    /// A wall-clock budget for performance tests. These run in a debug build next to other parallel tests
    /// (and, on a busy Mac, next to Xcode), so locally they get 3× the nominal time and GitHub's slower
    /// macOS runners 5×. A quadratic regression still costs tens of seconds to minutes on these inputs.
    static func budget(_ seconds: Double) -> Duration {
        .seconds(seconds * (ProcessInfo.processInfo.environment["CI"] == nil ? 3 : 5))
    }
}
