// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLotusHTTPBenchmarks",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftLotusHTTPBenchmarkServer", targets: ["SwiftLotusHTTPBenchmarkServer"]),
        .executable(name: "NIOHTTPBenchmarkServer", targets: ["NIOHTTPBenchmarkServer"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftLotusHTTPBenchmarkServer",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
            ]
        ),
        .executableTarget(
            name: "NIOHTTPBenchmarkServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
    ]
)
