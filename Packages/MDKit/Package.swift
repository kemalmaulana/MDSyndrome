// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MDKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
        .library(name: "PreviewKit", targets: ["PreviewKit"]),
        .library(name: "EditorKit", targets: ["EditorKit"]),
        .library(name: "SyntaxHighlighting", targets: ["SyntaxHighlighting"]),
    ],
    dependencies: [
        // gfm branch, pinned to an exact commit so app and package builds are reproducible.
        .package(url: "https://github.com/swiftlang/swift-cmark.git", revision: "0c8947bbd58c491c54aae114aca40621cddc8357"),
        // Native LaTeX typesetting (MIT). Bundles OFL/GUST-licensed math fonts (~7 MB).
        .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
    ],
    targets: [
        .target(name: "MarkdownCore", dependencies: [
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
        .target(name: "PreviewKit", dependencies: ["MarkdownCore", "SyntaxHighlighting", .product(name: "SwiftMath", package: "SwiftMath")]),
        .testTarget(name: "PreviewKitTests", dependencies: ["PreviewKit"]),
        .target(name: "EditorKit"),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
        .target(name: "SyntaxHighlighting"),
        .testTarget(name: "SyntaxHighlightingTests", dependencies: ["SyntaxHighlighting"]),
    ]
)
