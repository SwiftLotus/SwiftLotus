// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLotusRedis",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(name: "SwiftLotusRedis", targets: ["SwiftLotusRedis"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "SwiftLotusRedis",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
                .product(name: "RediStack", package: "RediStack"),
            ]
        ),
    ]
)
