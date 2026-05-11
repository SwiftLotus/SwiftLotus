import Foundation

public struct SwiftLotusRuntimeEnvironment: Sendable, Equatable {
    public let workerIndex: Int?
    public let workerCount: Int?
    public let reusePort: Bool
    public let runtimeDirectory: URL?
    public let name: String?

    public static var current: SwiftLotusRuntimeEnvironment {
        SwiftLotusRuntimeEnvironment(environment: ProcessInfo.processInfo.environment)
    }

    public init(environment: [String: String]) {
        self.workerIndex = environment["SWIFTLOTUS_WORKER_INDEX"].flatMap(Int.init)
        self.workerCount = environment["SWIFTLOTUS_WORKER_COUNT"].flatMap(Int.init)
        self.reusePort = environment["SWIFTLOTUS_REUSE_PORT"] == "1"
        self.runtimeDirectory = environment["SWIFTLOTUS_RUNTIME_DIR"].map {
            URL(fileURLWithPath: $0)
        }
        self.name = environment["SWIFTLOTUS_RUNTIME_NAME"]
    }
}

public enum SwiftLotusEndpoint: Sendable, Equatable {
    case tcp(host: String, port: Int)
    case unix(path: String)
}
