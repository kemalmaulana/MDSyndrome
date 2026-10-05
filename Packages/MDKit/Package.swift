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
        .library(name: "WebRenderKit", targets: ["WebRenderKit"]),
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
        .target(name: "PreviewKit", dependencies: ["MarkdownCore", "SyntaxHighlighting", "WebRenderKit", .product(name: "SwiftMath", package: "SwiftMath")]),
        .testTarget(name: "PreviewKitTests", dependencies: ["PreviewKit"]),
        .target(name: "EditorKit"),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
        .target(name: "SyntaxHighlighting"),
        .testTarget(name: "SyntaxHighlightingTests", dependencies: ["SyntaxHighlighting"]),
        // The only target that imports WebKit (PRD NF-1). The vendored mermaid, viz.js and KaTeX are in Resources
        // (see VENDORED.md); `.copy` keeps the folder layout the bundled page and the KaTeX CSS rely on.
        .target(name: "WebRenderKit", resources: [.copy("Resources")]),
        .testTarget(name: "WebRenderKitTests", dependencies: ["WebRenderKit"]),
    ]
)
