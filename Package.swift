// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameLibrary",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MacGameLibrary", targets: ["MacGameLibrary"])
    ],
    targets: [
        .target(
            name: "MacGameLibrary",
            path: "Sources/MacGameLibrary"
        )
    ]
)
