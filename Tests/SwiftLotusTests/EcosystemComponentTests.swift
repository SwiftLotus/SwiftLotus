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

    private var requestURI = "/"
    private var requestHost = ""

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestURI = head.uri
            requestHost = head.headers.first(name: "Host") ?? ""
        case .body:
            break
        case .end:
            var buffer = context.channel.allocator.buffer(capacity: 0)
            buffer.writeString("ok:\(requestURI)|\(requestHost)")

            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)

            context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}
