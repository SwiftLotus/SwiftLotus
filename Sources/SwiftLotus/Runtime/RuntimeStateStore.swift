import Foundation

public struct WorkerProcessRecord: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let pid: Int32
    public let workerIndex: Int
    public let startedAt: Date
    public let executable: String
    public let arguments: [String]
    public let reloadable: Bool

    public init(
        id: String,
        name: String,
        pid: Int32,
        workerIndex: Int,
        startedAt: Date,
        executable: String,
        arguments: [String],
        reloadable: Bool
    ) {
        self.id = id
        self.name = name
        self.pid = pid
        self.workerIndex = workerIndex
        self.startedAt = startedAt
        self.executable = executable
        self.arguments = arguments
        self.reloadable = reloadable
    }
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var records: [WorkerProcessRecord]

    public init(records: [WorkerProcessRecord] = []) {
        self.records = records
    }
}

public struct WorkerRuntimeStatus: Codable, Equatable, Sendable {
    public let name: String
    public let uri: String
    public let pid: Int32
    public let workerIndex: Int?
    public let connectionCount: Int
    public let startedAt: Date?
    public let updatedAt: Date
}

public final class RuntimeStateStore: @unchecked Sendable {
    public let runtimeDirectory: URL
    public let stateURL: URL
    public let statusDirectory: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(runtimeDirectory: URL) {
        self.runtimeDirectory = runtimeDirectory
        self.stateURL = runtimeDirectory.appendingPathComponent("workers.json")
        self.statusDirectory = runtimeDirectory.appendingPathComponent("status", isDirectory: true)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> RuntimeState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return RuntimeState()
        }
        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(RuntimeState.self, from: data)
    }

    public func save(_ state: RuntimeState) throws {
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    public func saveStatus(_ status: WorkerRuntimeStatus) throws {
        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(status)
        let url = statusDirectory.appendingPathComponent("\(status.pid).json")
        try data.write(to: url, options: .atomic)
    }

    public func loadStatuses() throws -> [WorkerRuntimeStatus] {
        guard FileManager.default.fileExists(atPath: statusDirectory.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(at: statusDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(WorkerRuntimeStatus.self, from: data)
            }
            .sorted { $0.pid < $1.pid }
    }
}
