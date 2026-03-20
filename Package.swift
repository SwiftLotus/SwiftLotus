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
        // 2. Add-on Ecosystem Targets
        .library(name: "SwiftLotusRedis", targets: ["SwiftLotusRedis"]),
        .library(name: "SwiftLotusMySQL", targets: ["SwiftLotusMySQL"]),
        .library(name: "SwiftLotusPostgres", targets: ["SwiftLotusPostgres"]),
        
        // Example
        .executable(name: "SwiftLotusExample", targets: ["SwiftLotusExample"]),
    ],
    dependencies: [
        // Core Networking Dependencies
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        
        // --- Add-on Ecosystem Dependencies ---
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.4.0"),
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.3.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.14.0"),
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
        
        // Add-on Targets
        .target(
            name: "SwiftLotusRedis",
            dependencies: [
                "SwiftLotus",
                .product(name: "RediStack", package: "RediStack"),
            ]
        ),
        .target(
            name: "SwiftLotusMySQL",
            dependencies: [
                "SwiftLotus",
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ]
        ),
        .target(
            name: "SwiftLotusPostgres",
            dependencies: [
                "SwiftLotus",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),

        // Tests & Example
        .executableTarget(
            name: "SwiftLotusExample",
            dependencies: ["SwiftLotus"]
        ),
        .testTarget(
            name: "SwiftLotusTests",
            dependencies: ["SwiftLotus"]),
    ]
)
