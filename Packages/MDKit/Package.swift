// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MDKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    dependencies: [
        // gfm branch, pinned to an exact commit so app and package builds are reproducible.
        .package(url: "https://github.com/swiftlang/swift-cmark.git", revision: "0c8947bbd58c491c54aae114aca40621cddc8357"),
    ],
    targets: [
        .target(name: "MarkdownCore", dependencies: [
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
    ]
)
