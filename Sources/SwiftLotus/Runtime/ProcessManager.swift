import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SwiftLotusProcessManagerError: Error {
    case processExecutionUnsupported
}

public struct ProcessStatusRow: Equatable, Sendable {
    public let record: WorkerProcessRecord
    public let isAlive: Bool
    public let runtimeStatus: WorkerRuntimeStatus?
}

public final class SwiftLotusProcessManager: @unchecked Sendable {
    public init() {}

    @discardableResult
    public func start(_ spec: WorkerProcessSpec) throws -> RuntimeState {
        let store = RuntimeStateStore(runtimeDirectory: spec.runtimeDirectory)
        var records: [WorkerProcessRecord] = []

        for index in 0..<spec.workerCount {
            let pid = try spawnWorker(spec, index: index)
            records.append(
                WorkerProcessRecord(
                    id: "\(spec.name)-\(index)",
                    name: spec.name,
                    pid: pid,
                    workerIndex: index,
                    startedAt: Date(),
                    executable: spec.executable,
                    arguments: spec.arguments,
                    reloadable: spec.reloadable
                )
            )
        }

        let state = RuntimeState(records: records)
        try store.save(state)
        return state
    }

    public func stop(runtimeDirectory: URL) throws {
        let store = RuntimeStateStore(runtimeDirectory: runtimeDirectory)
        let state = try store.load()
        for record in state.records {
            POSIXSignal.send(.terminate, to: record.pid)
        }
        try store.save(RuntimeState())
    }

    @discardableResult
    public func restart(_ spec: WorkerProcessSpec) throws -> RuntimeState {
        try stop(runtimeDirectory: spec.runtimeDirectory)
        return try start(spec)
    }

    public func reload(runtimeDirectory: URL) throws {
        let store = RuntimeStateStore(runtimeDirectory: runtimeDirectory)
        let state = try store.load()
        for record in state.records {
            POSIXSignal.send(.userReload, to: record.pid)
        }
    }

    public func status(runtimeDirectory: URL) throws -> [ProcessStatusRow] {
        let store = RuntimeStateStore(runtimeDirectory: runtimeDirectory)
        let state = try store.load()
        let statuses = try store.loadStatuses()
        let statusesByPID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.pid, $0) })

        return state.records.map { record in
            ProcessStatusRow(
                record: record,
                isAlive: POSIXSignal.isAlive(record.pid),
                runtimeStatus: statusesByPID[record.pid]
            )
        }
    }

    private func spawnWorker(_ spec: WorkerProcessSpec, index: Int) throws -> Int32 {
        #if os(macOS) || os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["SWIFTLOTUS_WORKER_INDEX"] = "\(index)"
        environment["SWIFTLOTUS_WORKER_COUNT"] = "\(spec.workerCount)"
        environment["SWIFTLOTUS_REUSE_PORT"] = spec.reusePort ? "1" : "0"
        environment["SWIFTLOTUS_RUNTIME_DIR"] = spec.runtimeDirectory.path
        environment["SWIFTLOTUS_RUNTIME_NAME"] = spec.name
        environment["SWIFTLOTUS_RELOADABLE"] = spec.reloadable ? "1" : "0"
        process.environment = environment

        let logDirectory = spec.runtimeDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logDirectory.appendingPathComponent("\(spec.name)-\(index).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        return process.processIdentifier
        #else
        throw SwiftLotusProcessManagerError.processExecutionUnsupported
        #endif
    }
}

public enum POSIXSignal {
    case terminate
    case userReload

    var rawValue: Int32 {
        switch self {
        case .terminate:
            return SIGTERM
        case .userReload:
            return SIGUSR1
        }
    }

    public static func send(_ signal: POSIXSignal, to pid: Int32) {
        #if os(macOS) || os(Linux)
        kill(pid, signal.rawValue)
        #endif
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        #if os(macOS) || os(Linux)
        return kill(pid, 0) == 0
        #else
        return false
        #endif
    }
}
