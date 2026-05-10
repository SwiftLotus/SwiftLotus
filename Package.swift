// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftLotus",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        // 1. Pure Core Framework
        .library(name: "SwiftLotus", targets: ["SwiftLotus"]),
        
        // Example
        .executable(name: "SwiftLotusExample", targets: ["SwiftLotusExample"]),
    ],
    dependencies: [
        // Core Networking Dependencies
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
    ],
    targets: [
        // Core Target
        .target(
            name: "SwiftLotus",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // Tests & Example
        .executableTarget(
            name: "SwiftLotusExample",
            dependencies: ["SwiftLotus"]
        ),
        .testTarget(
            name: "SwiftLotusTests",
            dependencies: [
                "SwiftLotus",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]),
    ]
)
