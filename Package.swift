// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftLotus",
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueSocket.git", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "SwiftLotus",
            dependencies: ["Socket"])
    ]
)
