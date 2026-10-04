import Foundation

extension Duration {
    /// A wall-clock budget for performance tests. GitHub's macOS runners are slower and run the
    /// parallel tests on few cores, so CI gets 5× headroom — still far below what a quadratic
    /// regression costs (tens of seconds to minutes on these inputs).
    static func budget(_ seconds: Double) -> Duration {
        .seconds(ProcessInfo.processInfo.environment["CI"] == nil ? seconds : seconds * 5)
    }
}
