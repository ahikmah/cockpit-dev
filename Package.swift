// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "CockpitDev",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CockpitDev",
            targets: ["CockpitDev"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0")
        // Note: SwiftGit2 will be added in Task 21 (Git Operations) once a SPM-compatible
        // fork or wrapper is configured. The upstream repo lacks proper SPM manifest support.
    ],
    targets: [
        .executableTarget(
            name: "CockpitDev",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio")
            ],
            path: "Sources/CockpitDev",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CockpitDevTests",
            dependencies: ["CockpitDev"],
            path: "Tests/CockpitDevTests"
        )
    ]
)
