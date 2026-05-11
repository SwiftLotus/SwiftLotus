import XCTest
import NIOCore
import NIOEmbedded
@testable import SwiftLotus

final class ConnectionRuntimeTests: XCTestCase {
    func testConnectionReadControlTogglesAutoRead() throws {
        let channel = EmbeddedChannel()
        let connection = Connection<TextProtocol>(channel: channel)

        try connection.pauseRead().wait()
        XCTAssertTrue(connection.isReadPaused)

        try connection.resumeRead().wait()
        XCTAssertFalse(connection.isReadPaused)

        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testWorkerReceivesBufferDrainAndErrorCallbacks() {
        let worker = SwiftLotus<TextProtocol>(name: "CallbackTest", uri: "tcp://127.0.0.1:0", enableSignalHandlers: false)
        let drainExpectation = expectation(description: "buffer drain")
        let errorExpectation = expectation(description: "error")

        worker.onBufferDrain = { connection in
            XCTAssertTrue(connection.isWritable)
            drainExpectation.fulfill()
        }
        worker.onError = { _, error in
            XCTAssertTrue(error is ChannelError)
            errorExpectation.fulfill()
        }

        let channel = EmbeddedChannel(handler: LotusHandler(worker: worker))
        channel.pipeline.fireChannelActive()
        channel.pipeline.fireChannelWritabilityChanged()
        channel.pipeline.fireErrorCaught(ChannelError.alreadyClosed)

        wait(for: [drainExpectation, errorExpectation], timeout: 1.0)
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testWorkerMetricsTrackConnectionsMessagesAndBackpressure() throws {
        let worker = SwiftLotus<TextProtocol>(name: "MetricsTest", uri: "tcp://127.0.0.1:0", enableSignalHandlers: false)
        let channel = EmbeddedChannel(handler: LotusHandler(worker: worker))
        channel.pipeline.fireChannelActive()

        let connection = try XCTUnwrap(worker.connections.values.first)
        try channel.writeInbound("hello")
        try connection.writeProtocolResponse("world").wait()
        channel.pipeline.fireChannelWritabilityChanged()
        channel.pipeline.fireErrorCaught(ChannelError.alreadyClosed)
        channel.pipeline.fireChannelInactive()

        let snapshot = worker.metrics.snapshot()
        XCTAssertEqual(snapshot.counters["connections.accepted"], 1)
        XCTAssertEqual(snapshot.counters["connections.closed"], 1)
        XCTAssertEqual(snapshot.counters["messages.received"], 1)
        XCTAssertEqual(snapshot.counters["messages.sent"], 1)
        XCTAssertEqual(snapshot.counters["backpressure.drain"], 1)
        XCTAssertEqual(snapshot.counters["errors"], 1)
        XCTAssertEqual(snapshot.gauges["connections.current"], 0)

        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testIdleEventInvokesCallbackAndClosesConnectionWhenConfigured() {
        let worker = SwiftLotus<TextProtocol>(name: "IdleTest", uri: "tcp://127.0.0.1:0", enableSignalHandlers: false)
        worker.closeIdleConnections = true

        let idleExpectation = expectation(description: "idle")
        worker.onIdle = { connection, event in
            XCTAssertEqual(event, .all)
            XCTAssertFalse(connection.isActive)
            idleExpectation.fulfill()
        }

        let channel = EmbeddedChannel(handler: LotusHandler(worker: worker))
        channel.pipeline.fireChannelActive()
        channel.pipeline.fireUserInboundEventTriggered(IdleStateHandler.IdleStateEvent.all)

        wait(for: [idleExpectation], timeout: 1.0)
        XCTAssertFalse(channel.isActive)
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testReconnectPolicyTracksAttempts() {
        let policy = ReconnectPolicy.fixedDelay(maxAttempts: 3, delay: .milliseconds(10))

        XCTAssertTrue(policy.shouldReconnect(afterFailedAttempt: 1))
        XCTAssertTrue(policy.shouldReconnect(afterFailedAttempt: 2))
        XCTAssertFalse(policy.shouldReconnect(afterFailedAttempt: 3))
    }

    func testWorkerStatusReportsStaticRuntimeSnapshot() {
        let worker = SwiftLotus<TextProtocol>(name: "StatusTest", count: 2, uri: "tcp://127.0.0.1:0", enableSignalHandlers: false)

        let status = worker.status

        XCTAssertEqual(status.name, "StatusTest")
        XCTAssertEqual(status.uri, "tcp://127.0.0.1:0")
        XCTAssertEqual(status.threadCount, 2)
        XCTAssertEqual(status.connectionCount, 0)
        XCTAssertFalse(status.isRunning)
        XCTAssertNil(status.startedAt)
    }
}
