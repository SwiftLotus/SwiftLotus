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
        .library(
            name: "SwiftLotus",
            targets: ["SwiftLotus"]),
        .executable(
            name: "SwiftLotusExample",
            targets: ["SwiftLotusExample"]),
    ],
    dependencies: [
        // SwiftNIO for high-performance networking
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // SwiftLog for logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        // SwiftNIO SSL for TLS support
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        // Swift-DocC Plugin for documentation generation
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
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
        .executableTarget(
            name: "SwiftLotusExample",
            dependencies: ["SwiftLotus"]
        ),
        .testTarget(
            name: "SwiftLotusTests",
            dependencies: ["SwiftLotus"]),
    ]
)
