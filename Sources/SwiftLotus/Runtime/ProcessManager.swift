import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SwiftLotusProcessManagerError: Error, Equatable {
    case processExecutionUnsupported
    case workersAlreadyRunning([WorkerProcessRecord])
    case workerExitTimedOut([WorkerProcessRecord])
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
        let existingState = try store.load()
        let liveRecords = existingState.records.filter { POSIXSignal.isAlive($0.pid) }
        guard liveRecords.isEmpty else {
            throw SwiftLotusProcessManagerError.workersAlreadyRunning(liveRecords)
        }

        if !existingState.records.isEmpty {
            try store.save(RuntimeState())
            try store.clearStatuses()
        }

        var records: [WorkerProcessRecord] = []

        do {
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
        } catch {
            terminate(records, timeout: 1.0)
            try? store.save(RuntimeState())
            try? store.clearStatuses()
            throw error
        }

        let state = RuntimeState(records: records)
        try store.save(state)
        return state
    }

    public func stop(runtimeDirectory: URL, timeout: TimeInterval = 5.0) throws {
        let store = RuntimeStateStore(runtimeDirectory: runtimeDirectory)
        let state = try store.load()
        let remaining = terminate(state.records, timeout: timeout)
        if !remaining.isEmpty {
            throw SwiftLotusProcessManagerError.workerExitTimedOut(remaining)
        }
        try store.save(RuntimeState())
        try store.clearStatuses()
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

    @discardableResult
    private func terminate(_ records: [WorkerProcessRecord], timeout: TimeInterval) -> [WorkerProcessRecord] {
        var liveRecords = records.filter { POSIXSignal.isAlive($0.pid) }
        for record in liveRecords {
            POSIXSignal.send(.terminate, to: record.pid)
        }

        liveRecords = waitForExit(liveRecords, timeout: timeout)
        guard !liveRecords.isEmpty else {
            return []
        }

        for record in liveRecords {
            POSIXSignal.send(.forceKill, to: record.pid)
        }
        return waitForExit(liveRecords, timeout: 1.0)
    }

    private func waitForExit(_ records: [WorkerProcessRecord], timeout: TimeInterval) -> [WorkerProcessRecord] {
        var liveRecords = records.filter { POSIXSignal.isAlive($0.pid) }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while !liveRecords.isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            liveRecords = liveRecords.filter { POSIXSignal.isAlive($0.pid) }
        }
        return liveRecords
    }
}

public enum POSIXSignal {
    case terminate
    case userReload
    case forceKill

    var rawValue: Int32 {
        switch self {
        case .terminate:
            return SIGTERM
        case .userReload:
            return SIGUSR1
        case .forceKill:
            return SIGKILL
        }
    }

    @discardableResult
    public static func send(_ signal: POSIXSignal, to pid: Int32) -> Bool {
        #if os(macOS) || os(Linux)
        return kill(pid, signal.rawValue) == 0
        #else
        return false
        #endif
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        #if os(macOS) || os(Linux)
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return false
        #endif
    }
}
