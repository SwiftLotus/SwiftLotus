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
