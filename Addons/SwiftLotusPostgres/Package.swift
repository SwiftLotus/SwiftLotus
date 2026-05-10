// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLotusPostgres",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(name: "SwiftLotusPostgres", targets: ["SwiftLotusPostgres"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.14.0"),
    ],
    targets: [
        .target(
            name: "SwiftLotusPostgres",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
    ]
)
