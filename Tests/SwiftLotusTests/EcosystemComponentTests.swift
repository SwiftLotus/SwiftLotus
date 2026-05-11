import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
@testable import SwiftLotus

final class EcosystemComponentTests: XCTestCase {
    func testHTTPClientRequestParsesURLAndDefaultPort() throws {
        let request = try SwiftLotusHTTPRequest(method: .GET, url: "http://example.com/api?q=1")

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 80)
        XCTAssertEqual(request.pathWithQuery, "/api?q=1")
        XCTAssertFalse(request.isTLS)
    }

    func testHTTPClientPerformsPlaintextRequest() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withPipeliningAssistance: true,
                        withServerUpgrade: nil,
                        withErrorHandling: true
                    )
                    try channel.pipeline.syncOperations.addHandler(TestHTTPServerHandler())
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        addTeardownBlock {
            try? server.close().wait()
            try? group.syncShutdownGracefully()
        }

        let port = try XCTUnwrap(server.localAddress?.port)
        let client = SwiftLotusHTTPClient(group: group)

        let response = try await client.get("http://127.0.0.1:\(port)/health?ready=1")

        XCTAssertEqual(response.status, HTTPResponseStatus.ok)
        XCTAssertEqual(response.body, "ok:/health?ready=1|127.0.0.1:\(port)")
    }

    func testHTTPClientFailsWhenConnectionClosesBeforeResponseCompletes() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(CloseOnActiveHandler())
            }
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: false)
            .bind(host: "127.0.0.1", port: 0)
            .get()

        addTeardownBlock {
            try? server.close().wait()
            try? group.syncShutdownGracefully()
        }

        let port = try XCTUnwrap(server.localAddress?.port)
        let client = SwiftLotusHTTPClient(group: group)

        do {
            _ = try await withTimeout(seconds: 0.5) {
                try await client.get("http://127.0.0.1:\(port)/will-close")
            }
            XCTFail("Expected incomplete response to fail")
        } catch TestTimeoutError.timedOut {
            XCTFail("HTTP client request should complete when the channel closes")
        } catch {
            // Expected: the connection closed before a complete response arrived.
        }
    }

    func testHTTPClientRejectsOversizedResponseBody() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withPipeliningAssistance: true,
                        withServerUpgrade: nil,
                        withErrorHandling: true
                    )
                    try channel.pipeline.syncOperations.addHandler(TestHTTPServerHandler(body: "too-large"))
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        addTeardownBlock {
            try? server.close().wait()
            try? group.syncShutdownGracefully()
        }

        let port = try XCTUnwrap(server.localAddress?.port)
        let client = SwiftLotusHTTPClient(group: group, maxResponseBodyBytes: 3)

        do {
            _ = try await client.get("http://127.0.0.1:\(port)/large")
            XCTFail("Expected oversized response body to fail")
        } catch {
            XCTAssertEqual(error as? SwiftLotusError, .payloadTooLarge(maximum: 3))
        }
    }

    func testHTTPClientTimesOutWhenServerDoesNotRespond() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withPipeliningAssistance: true,
                        withServerUpgrade: nil,
                        withErrorHandling: true
                    )
                    try channel.pipeline.syncOperations.addHandler(SilentHTTPServerHandler())
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        addTeardownBlock {
            try? server.close().wait()
            try? group.syncShutdownGracefully()
        }

        let port = try XCTUnwrap(server.localAddress?.port)
        let client = SwiftLotusHTTPClient(group: group, requestTimeout: .milliseconds(50))

        do {
            _ = try await withTimeout(seconds: 1.0) {
                try await client.get("http://127.0.0.1:\(port)/silent")
            }
            XCTFail("Expected request timeout")
        } catch TestTimeoutError.timedOut {
            XCTFail("HTTP client timeout should complete the request")
        } catch {
            XCTAssertEqual(error as? SwiftLotusError, .requestTimedOut)
        }
    }

    func testEventBusPublishesAndUnsubscribes() async {
        let bus = SwiftLotusEventBus<String>()
        let recorder = MessageRecorder()
        let token = bus.subscribe("jobs") { message in
            recorder.append(message)
        }

        await bus.publish("jobs", "first")
        bus.unsubscribe(token)
        await bus.publish("jobs", "second")

        XCTAssertEqual(recorder.messages, ["first"])
    }

    func testScheduleCalculatesNextIntervalAndDailyRun() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(SwiftLotusSchedule.every(seconds: 5).nextRun(after: start), start.addingTimeInterval(5))

        let calendar = Calendar(identifier: .gregorian)
        let daily = SwiftLotusSchedule.daily(hour: 23, minute: 0, second: 0, calendar: calendar)
        let next = try XCTUnwrap(daily.nextRun(after: start))
        let components = calendar.dateComponents([.hour, .minute, .second], from: next)

        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
        XCTAssertGreaterThan(next, start)
    }

    func testScheduleRejectsNonPositiveOrNonFiniteIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(SwiftLotusSchedule.once(after: 0).nextRun(after: start))
        XCTAssertNil(SwiftLotusSchedule.every(seconds: -1).nextRun(after: start))
        XCTAssertNil(SwiftLotusSchedule.every(seconds: .infinity).nextRun(after: start))
    }

    func testTimerRejectsNonPositiveOrNonFiniteIntervals() {
        XCTAssertTrue(SwiftLotusTimer.add(timeInterval: 0) {}.isCancelled)
        XCTAssertTrue(SwiftLotusTimer.add(timeInterval: -.infinity) {}.isCancelled)
    }

    func testMetricsCountersGaugesAndDurationsSnapshot() {
        let metrics = SwiftLotusMetrics()

        metrics.incrementCounter("messages", by: 2)
        metrics.setGauge("connections", value: 7)
        metrics.recordDuration("handler", seconds: 0.25)
        let snapshot = metrics.snapshot()

        XCTAssertEqual(snapshot.counters["messages"], 2)
        XCTAssertEqual(snapshot.gauges["connections"], 7)
        XCTAssertEqual(snapshot.durations["handler"]?.count, 1)
        XCTAssertEqual(snapshot.durations["handler"]?.totalSeconds, 0.25)
    }
}

private final class TestHTTPServerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let body: String?
    private var requestURI = "/"
    private var requestHost = ""

    init(body: String? = nil) {
        self.body = body
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestURI = head.uri
            requestHost = head.headers.first(name: "Host") ?? ""
        case .body:
            break
        case .end:
            var buffer = context.channel.allocator.buffer(capacity: 0)
            buffer.writeString(body ?? "ok:\(requestURI)|\(requestHost)")

            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)

            context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

private enum TestTimeoutError: Error {
    case timedOut
}

private final class CloseOnActiveHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    func channelActive(context: ChannelHandlerContext) {
        context.close(promise: nil)
    }
}

private final class SilentHTTPServerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        _ = unwrapInboundIn(data)
    }
}

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TestTimeoutError.timedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
