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

public struct SwiftLotusSupervisorOptions: Equatable, Sendable {
    public let pollInterval: TimeInterval
    public let maxIterations: Int?
    public let maxRestartsPerWorker: Int?
    public let restartDelay: TimeInterval

    public init(
        pollInterval: TimeInterval = 1.0,
        maxIterations: Int? = nil,
        maxRestartsPerWorker: Int? = nil,
        restartDelay: TimeInterval = 0.1
    ) {
        self.pollInterval = pollInterval
        self.maxIterations = maxIterations
        self.maxRestartsPerWorker = maxRestartsPerWorker
        self.restartDelay = restartDelay
    }
}

public struct SwiftLotusRollingReloadOptions: Equatable, Sendable {
    public let timeoutPerWorker: TimeInterval
    public let restartDelay: TimeInterval

    public init(timeoutPerWorker: TimeInterval = 5.0, restartDelay: TimeInterval = 0.1) {
        self.timeoutPerWorker = timeoutPerWorker
        self.restartDelay = restartDelay
    }
}

final class SwiftLotusProcessControl: @unchecked Sendable {
    let spawn: (WorkerProcessSpec, Int) throws -> Int32
    let sendSignal: (POSIXSignal, Int32) -> Bool
    let isAlive: (Int32) -> Bool
    let sleep: (TimeInterval) -> Void

    init(
        spawn: @escaping (WorkerProcessSpec, Int) throws -> Int32,
        sendSignal: @escaping (POSIXSignal, Int32) -> Bool,
        isAlive: @escaping (Int32) -> Bool,
        sleep: @escaping (TimeInterval) -> Void
    ) {
        self.spawn = spawn
        self.sendSignal = sendSignal
        self.isAlive = isAlive
        self.sleep = sleep
    }

    static let live = SwiftLotusProcessControl(
        spawn: SwiftLotusProcessManager.spawnWorkerProcess,
        sendSignal: POSIXSignal.send,
        isAlive: POSIXSignal.isAlive,
        sleep: Thread.sleep(forTimeInterval:)
    )
}

public final class SwiftLotusProcessManager: @unchecked Sendable {
    private let control: SwiftLotusProcessControl

    public convenience init() {
        self.init(control: .live)
    }

    init(control: SwiftLotusProcessControl) {
        self.control = control
    }

    @discardableResult
    public func start(_ spec: WorkerProcessSpec) throws -> RuntimeState {
        let store = RuntimeStateStore(runtimeDirectory: spec.runtimeDirectory)
        let existingState = try store.load()
        let liveRecords = existingState.records.filter { control.isAlive($0.pid) }
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
                records.append(try spawnWorker(spec, index: index))
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
            _ = control.sendSignal(.userReload, record.pid)
        }
    }

    @discardableResult
    public func supervise(
        _ spec: WorkerProcessSpec,
        options: SwiftLotusSupervisorOptions = SwiftLotusSupervisorOptions()
    ) throws -> RuntimeState {
        let store = RuntimeStateStore(runtimeDirectory: spec.runtimeDirectory)
        var state = try store.load()
        var restartCountsByIndex: [Int: Int] = [:]
        var iterations = 0

        while options.maxIterations == nil || iterations < options.maxIterations! {
            state = try reconcileWorkers(
                spec,
                state: state,
                restartCountsByIndex: &restartCountsByIndex,
                maxRestartsPerWorker: options.maxRestartsPerWorker,
                restartDelay: options.restartDelay
            )
            try store.save(state)

            iterations += 1
            if let maxIterations = options.maxIterations, iterations >= maxIterations {
                break
            }
            control.sleep(options.pollInterval)
        }

        return state
    }

    @discardableResult
    public func rollingReload(
        _ spec: WorkerProcessSpec,
        options: SwiftLotusRollingReloadOptions = SwiftLotusRollingReloadOptions()
    ) throws -> RuntimeState {
        let store = RuntimeStateStore(runtimeDirectory: spec.runtimeDirectory)
        var state = try store.load()
        var records = state.records.sorted { $0.workerIndex < $1.workerIndex }

        for record in records {
            if control.isAlive(record.pid) {
                _ = control.sendSignal(record.reloadable ? .userReload : .terminate, record.pid)
                let remaining = waitForExit([record], timeout: options.timeoutPerWorker)
                if !remaining.isEmpty {
                    let forcedRemaining = terminate(remaining, timeout: 0)
                    if !forcedRemaining.isEmpty {
                        throw SwiftLotusProcessManagerError.workerExitTimedOut(forcedRemaining)
                    }
                }
            }

            control.sleep(options.restartDelay)
            let replacement = try spawnWorker(spec, index: record.workerIndex)
            records.removeAll { $0.workerIndex == record.workerIndex }
            records.append(replacement)
            records.sort { $0.workerIndex < $1.workerIndex }
            state = RuntimeState(records: records)
            try store.save(state)
        }

        return state
    }

    public func status(runtimeDirectory: URL) throws -> [ProcessStatusRow] {
        let store = RuntimeStateStore(runtimeDirectory: runtimeDirectory)
        let state = try store.load()
        let statuses = try store.loadStatuses()
        let statusesByPID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.pid, $0) })

        return state.records.map { record in
            ProcessStatusRow(
                record: record,
                isAlive: control.isAlive(record.pid),
                runtimeStatus: statusesByPID[record.pid]
            )
        }
    }

    private func spawnWorker(_ spec: WorkerProcessSpec, index: Int) throws -> WorkerProcessRecord {
        let pid = try control.spawn(spec, index)
        return WorkerProcessRecord(
            id: "\(spec.name)-\(index)",
            name: spec.name,
            pid: pid,
            workerIndex: index,
            startedAt: Date(),
            executable: spec.executable,
            arguments: spec.arguments,
            reloadable: spec.reloadable
        )
    }

    private func reconcileWorkers(
        _ spec: WorkerProcessSpec,
        state: RuntimeState,
        restartCountsByIndex: inout [Int: Int],
        maxRestartsPerWorker: Int?,
        restartDelay: TimeInterval
    ) throws -> RuntimeState {
        var liveRecords = state.records.filter { control.isAlive($0.pid) }
        let liveIndexes = Set(liveRecords.map(\.workerIndex))

        for index in 0..<spec.workerCount where !liveIndexes.contains(index) {
            let restartCount = restartCountsByIndex[index, default: 0]
            if let maxRestartsPerWorker, restartCount >= maxRestartsPerWorker {
                continue
            }
            control.sleep(restartCount == 0 ? 0 : restartDelay)
            let replacement = try spawnWorker(spec, index: index)
            restartCountsByIndex[index] = restartCount + 1
            liveRecords.removeAll { $0.workerIndex == index }
            liveRecords.append(replacement)
        }

        return RuntimeState(records: liveRecords.sorted { $0.workerIndex < $1.workerIndex })
    }

    static func spawnWorkerProcess(_ spec: WorkerProcessSpec, index: Int) throws -> Int32 {
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
        defer { try? logHandle.close() }
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
        var liveRecords = records.filter { control.isAlive($0.pid) }
        for record in liveRecords {
            _ = control.sendSignal(.terminate, record.pid)
        }

        liveRecords = waitForExit(liveRecords, timeout: timeout)
        guard !liveRecords.isEmpty else {
            return []
        }

        for record in liveRecords {
            _ = control.sendSignal(.forceKill, record.pid)
        }
        return waitForExit(liveRecords, timeout: 1.0)
    }

    private func waitForExit(_ records: [WorkerProcessRecord], timeout: TimeInterval) -> [WorkerProcessRecord] {
        var liveRecords = records.filter { control.isAlive($0.pid) }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while !liveRecords.isEmpty && Date() < deadline {
            control.sleep(0.05)
            liveRecords = liveRecords.filter { control.isAlive($0.pid) }
        }
        return liveRecords
    }
}

public enum POSIXSignal: Equatable, Sendable {
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
