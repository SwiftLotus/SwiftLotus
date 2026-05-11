import XCTest
import Foundation
@testable import SwiftLotus

final class RuntimeManagerTests: XCTestCase {
    func testCLIStartCommandParsesWorkerSpec() throws {
        let command = try SwiftLotusCLICommand.parse([
            "swiftlotus",
            "start",
            "--name", "chat",
            "--command", "/tmp/chat-server",
            "--workers", "3",
            "--runtime-dir", "/tmp/swiftlotus",
            "--reuse-port"
        ])

        guard case .start(let spec) = command else {
            return XCTFail("Expected start command")
        }

        XCTAssertEqual(spec.name, "chat")
        XCTAssertEqual(spec.executable, "/tmp/chat-server")
        XCTAssertEqual(spec.workerCount, 3)
        XCTAssertEqual(spec.runtimeDirectory.path, "/tmp/swiftlotus")
        XCTAssertTrue(spec.reusePort)
    }

    func testCLIParsesSuperviseAndRollingReloadCommands() throws {
        let supervise = try SwiftLotusCLICommand.parse([
            "swiftlotus",
            "supervise",
            "--name", "chat",
            "--command", "/tmp/chat-server",
            "--workers", "2",
            "--runtime-dir", "/tmp/swiftlotus",
        ])
        let rollingReload = try SwiftLotusCLICommand.parse([
            "swiftlotus",
            "rolling-reload",
            "--name", "chat",
            "--command", "/tmp/chat-server",
            "--workers", "2",
            "--runtime-dir", "/tmp/swiftlotus",
        ])

        guard case .supervise(let superviseSpec) = supervise else {
            return XCTFail("Expected supervise command")
        }
        guard case .rollingReload(let reloadSpec) = rollingReload else {
            return XCTFail("Expected rolling-reload command")
        }
        XCTAssertEqual(superviseSpec.workerCount, 2)
        XCTAssertEqual(reloadSpec.workerCount, 2)
    }

    func testRuntimeStateStorePersistsWorkerRecords() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlotus-runtime-tests-\(UUID().uuidString)")
        let store = RuntimeStateStore(runtimeDirectory: directory)
        let record = WorkerProcessRecord(
            id: "chat-0",
            name: "chat",
            pid: 12345,
            workerIndex: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            executable: "/tmp/chat-server",
            arguments: ["--port", "2346"],
            reloadable: true
        )

        try store.save(RuntimeState(records: [record]))
        let loaded = try store.load()

        XCTAssertEqual(loaded.records, [record])
        try? FileManager.default.removeItem(at: directory)
    }

    func testRuntimeStateStoreClearsStatusFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlotus-runtime-status-tests-\(UUID().uuidString)")
        let store = RuntimeStateStore(runtimeDirectory: directory)
        let status = WorkerRuntimeStatus(
            name: "chat",
            uri: "tcp://127.0.0.1:2346",
            pid: 12345,
            workerIndex: 0,
            connectionCount: 10,
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try store.saveStatus(status)
        XCTAssertEqual(try store.loadStatuses(), [status])

        try store.clearStatuses()

        XCTAssertTrue(try store.loadStatuses().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    func testProcessManagerRefusesToStartWhenWorkersAreAlreadyRunning() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlotus-running-tests-\(UUID().uuidString)")
        let store = RuntimeStateStore(runtimeDirectory: directory)
        let record = WorkerProcessRecord(
            id: "chat-0",
            name: "chat",
            pid: ProcessInfo.processInfo.processIdentifier,
            workerIndex: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            executable: "/tmp/chat-server",
            arguments: [],
            reloadable: true
        )
        try store.save(RuntimeState(records: [record]))

        let spec = WorkerProcessSpec(
            name: "chat",
            executable: "/tmp/chat-server",
            runtimeDirectory: directory
        )

        XCTAssertThrowsError(try SwiftLotusProcessManager().start(spec)) { error in
            guard case SwiftLotusProcessManagerError.workersAlreadyRunning(let records) = error else {
                return XCTFail("Expected workersAlreadyRunning, got \(error)")
            }
            XCTAssertEqual(records, [record])
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func testSupervisorRestartsMissingWorker() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlotus-supervisor-tests-\(UUID().uuidString)")
        let store = RuntimeStateStore(runtimeDirectory: directory)
        let staleRecord = WorkerProcessRecord(
            id: "chat-0",
            name: "chat",
            pid: 1,
            workerIndex: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            executable: "/tmp/chat-server",
            arguments: [],
            reloadable: true
        )
        try store.save(RuntimeState(records: [staleRecord]))

        var spawned: [(String, Int)] = []
        var nextPID: Int32 = 100
        let control = SwiftLotusProcessControl(
            spawn: { spec, index in
                spawned.append((spec.name, index))
                defer { nextPID += 1 }
                return nextPID
            },
            sendSignal: { _, _ in true },
            isAlive: { $0 >= 100 },
            sleep: { _ in }
        )
        let manager = SwiftLotusProcessManager(control: control)
        let spec = WorkerProcessSpec(
            name: "chat",
            executable: "/tmp/chat-server",
            runtimeDirectory: directory
        )

        let state = try manager.supervise(
            spec,
            options: SwiftLotusSupervisorOptions(pollInterval: 0, maxIterations: 1)
        )

        XCTAssertEqual(spawned.map(\.1), [0])
        XCTAssertEqual(state.records.map(\.pid), [100])
        XCTAssertEqual(try store.load().records.map(\.pid), [100])
        try? FileManager.default.removeItem(at: directory)
    }

    func testRollingReloadReplacesWorkersOneAtATime() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlotus-rolling-reload-tests-\(UUID().uuidString)")
        let store = RuntimeStateStore(runtimeDirectory: directory)
        let records = [
            WorkerProcessRecord(
                id: "chat-0",
                name: "chat",
                pid: 1,
                workerIndex: 0,
                startedAt: Date(timeIntervalSince1970: 100),
                executable: "/tmp/chat-server",
                arguments: [],
                reloadable: true
            ),
            WorkerProcessRecord(
                id: "chat-1",
                name: "chat",
                pid: 2,
                workerIndex: 1,
                startedAt: Date(timeIntervalSince1970: 100),
                executable: "/tmp/chat-server",
                arguments: [],
                reloadable: true
            ),
        ]
        try store.save(RuntimeState(records: records))

        var live: Set<Int32> = [1, 2]
        var nextPID: Int32 = 10
        var sentSignals: [(POSIXSignal, Int32)] = []
        let control = SwiftLotusProcessControl(
            spawn: { _, _ in
                defer { nextPID += 1 }
                live.insert(nextPID)
                return nextPID
            },
            sendSignal: { signal, pid in
                sentSignals.append((signal, pid))
                live.remove(pid)
                return true
            },
            isAlive: { live.contains($0) },
            sleep: { _ in }
        )
        let manager = SwiftLotusProcessManager(control: control)
        let spec = WorkerProcessSpec(
            name: "chat",
            executable: "/tmp/chat-server",
            workerCount: 2,
            runtimeDirectory: directory
        )

        let state = try manager.rollingReload(
            spec,
            options: SwiftLotusRollingReloadOptions(timeoutPerWorker: 0, restartDelay: 0)
        )

        XCTAssertEqual(sentSignals.map { "\($0.0):\($0.1)" }, ["userReload:1", "userReload:2"])
        XCTAssertEqual(state.records.map(\.workerIndex), [0, 1])
        XCTAssertEqual(state.records.map(\.pid), [10, 11])
        try? FileManager.default.removeItem(at: directory)
    }

    func testRuntimeEnvironmentReadsWorkerVariables() {
        let environment = SwiftLotusRuntimeEnvironment(environment: [
            "SWIFTLOTUS_WORKER_INDEX": "2",
            "SWIFTLOTUS_WORKER_COUNT": "4",
            "SWIFTLOTUS_REUSE_PORT": "1",
            "SWIFTLOTUS_RUNTIME_DIR": "/tmp/swiftlotus",
            "SWIFTLOTUS_RUNTIME_NAME": "chat"
        ])

        XCTAssertEqual(environment.workerIndex, 2)
        XCTAssertEqual(environment.workerCount, 4)
        XCTAssertTrue(environment.reusePort)
        XCTAssertEqual(environment.runtimeDirectory?.path, "/tmp/swiftlotus")
        XCTAssertEqual(environment.name, "chat")
    }
}
