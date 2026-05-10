// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLotusMySQL",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(name: "SwiftLotusMySQL", targets: ["SwiftLotusMySQL"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SwiftLotusMySQL",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ]
        ),
    ]
)
