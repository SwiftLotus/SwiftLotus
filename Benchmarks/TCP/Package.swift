// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLotusTCPBenchmarks",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftLotusTCPBenchmarkServer", targets: ["SwiftLotusTCPBenchmarkServer"]),
        .executable(name: "NIOTCPBenchmarkServer", targets: ["NIOTCPBenchmarkServer"]),
        .executable(name: "TCPBenchmarkClient", targets: ["TCPBenchmarkClient"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftLotusTCPBenchmarkServer",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
            ]
        ),
        .executableTarget(
            name: "NIOTCPBenchmarkServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "TCPBenchmarkClient",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
    ]
)
