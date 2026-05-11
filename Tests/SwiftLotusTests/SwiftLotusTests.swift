import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOEmbedded
import NIOConcurrencyHelpers
@testable import SwiftLotus

final class MessageRecorder: @unchecked Sendable {
    private let lock = NIOLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock {
            values.append(value)
        }
    }

    var messages: [String] {
        lock.withLock { values }
    }
}

final class SwiftLotusTests: XCTestCase {
    
    // MARK: - Core & TextProtocol Tests
    
    func testTextProtocolEncoding() {
        let allocator = ByteBufferAllocator()
        let buffer = TextProtocol.encode(data: "Hello", allocator: allocator)
        
        var input = buffer
        let _ = TextProtocol.decode(buffer: &input)
        
        // TextProtocol input() includes newline, decode removes it?
        // Wait, input() returns length. decode() reads string.
        // Let's manually verify decode logic which trims newline.
        
        // Actually, TextProtocol.encode adds \n.
        // Let's verify buffer content.
        XCTAssertEqual(buffer.getString(at: 0, length: buffer.readableBytes), "Hello\n")
    }
    
    func testTextProtocolInput() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(string: "Hello\nWorld")
        
        let len = try! TextProtocol.input(buffer: &buffer)
        XCTAssertEqual(len, 6) // "Hello\n" is 6 chars
    }

    func testTextProtocolRejectsOversizedLineWithoutDelimiter() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: TextProtocol.maxPackageSize + 1)
        buffer.writeRepeatingByte(65, count: TextProtocol.maxPackageSize + 1)

        XCTAssertThrowsError(try TextProtocol.input(buffer: &buffer)) { error in
            XCTAssertEqual(error as? SwiftLotusError, .payloadTooLarge(maximum: TextProtocol.maxPackageSize))
        }
    }

    func testTextProtocolDecodingRemovesCRLFDelimiter() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(string: "hello\r\n")

        let decoded = TextProtocol.decode(buffer: &buffer)

        XCTAssertEqual(decoded, "hello")
    }
    
    // MARK: - HttpProtocol Tests
    
    func testHttpRequestParsing() async {
        // Mock a request
        let uri = "/test?name=Lotus&foo=bar"
        let headers: HTTPHeaders = ["Cookie": "LOTUSSESSID=abc12345; user=admin"]
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)
        
        let request = HttpRequest(head: head, body: nil)
        
        // Test Query
        XCTAssertEqual(request.query["name"], "Lotus")
        XCTAssertEqual(request.query["foo"], "bar")
        
        // Test Cookies
        XCTAssertEqual(request.cookies["user"], "admin")
        XCTAssertEqual(request.sessionId, "abc12345")
        
        // Test Session
        await SessionManager.shared.set("abc12345", data: ["login": "true"])
        let sessionData = await request.session()
        XCTAssertEqual(sessionData["login"], "true")
    }
    
    func testHttpResponseCookies() {
        var response = HttpResponse(body: "ok")
        response.setCookie(name: "token", value: "xyz", maxAge: 3600)
        
        XCTAssertTrue(response.headers.contains(name: "Set-Cookie"))
        let cookie = response.headers["Set-Cookie"].first
        XCTAssertTrue(cookie?.contains("token=xyz") ?? false)
        XCTAssertTrue(cookie?.contains("Max-Age=3600") ?? false)
    }

    func testHttpSendAddsContentLengthForKnownBody() async throws {
        let channel = EmbeddedChannel()
        let connection = Connection<HttpProtocol>(channel: channel)

        try await connection.send(HttpResponse(body: "OK"))

        let part = try XCTUnwrap(try channel.readOutbound(as: HTTPServerResponsePart.self))
        guard case .head(let head) = part else {
            return XCTFail("Expected response head")
        }
        XCTAssertEqual(head.headers["Content-Length"].first, "2")

        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testHttpSyncMessageHandlerWritesResponseWithoutTaskHop() throws {
        let worker = SwiftLotus<HttpProtocol>(name: "HTTPFastPathTest", uri: "http://127.0.0.1:0", enableSignalHandlers: false)
        worker.onMessageSync = { connection, request in
            var headers = HTTPHeaders()
            headers.add(name: "Connection", value: request.head.isKeepAlive ? "keep-alive" : "close")
            connection.writeHTTPResponse(HttpResponse(body: "OK", headers: headers), closeAfterFlush: !request.head.isKeepAlive)
        }

        let channel = EmbeddedChannel(handler: LotusHttpHandler(worker: worker))
        channel.pipeline.fireChannelActive()

        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "keep-alive")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/", headers: headers)

        try channel.writeInbound(HTTPServerRequestPart.head(head))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let responseHeadPart = try XCTUnwrap(try channel.readOutbound(as: HTTPServerResponsePart.self))
        guard case .head(let responseHead) = responseHeadPart else {
            return XCTFail("Expected response head")
        }
        XCTAssertEqual(responseHead.headers["Content-Length"].first, "2")
        XCTAssertEqual(responseHead.headers["Connection"].first, "keep-alive")

        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testHttpRequestBodyUsesReaderIndex() throws {
        let worker = SwiftLotus<HttpProtocol>(name: "HTTPBodyReaderIndexTest", uri: "http://127.0.0.1:0", enableSignalHandlers: false)
        let receivedBodies = MessageRecorder()

        worker.onMessageSync = { _, request in
            receivedBodies.append(request.body ?? "")
        }

        let channel = EmbeddedChannel(handler: LotusHttpHandler(worker: worker))
        channel.pipeline.fireChannelActive()

        let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
        var body = channel.allocator.buffer(string: "xxpayload")
        body.moveReaderIndex(forwardBy: 2)

        try channel.writeInbound(HTTPServerRequestPart.head(head))
        try channel.writeInbound(HTTPServerRequestPart.body(body))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        XCTAssertEqual(receivedBodies.messages, ["payload"])
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testTLSSchemeRequiresSSLContext() async throws {
        let worker = SwiftLotus<TextProtocol>(uri: "ssl://256.256.256.256:1234", enableSignalHandlers: false)

        do {
            try await worker.run()
            XCTFail("Expected TLS context validation to fail before binding")
        } catch {
            XCTAssertEqual(error as? SwiftLotusError, .tlsContextRequired(scheme: "ssl"))
        }
    }
    
    // MARK: - FrameProtocol Tests
    
    func testFrameProtocol() {
        let allocator = ByteBufferAllocator()
        let data = "SwiftLotus"
        let buffer = FrameProtocol.encode(data: data, allocator: allocator)
        
        // Header is 4 bytes length
        XCTAssertEqual(buffer.readableBytes, 4 + 10)
        
        var input = buffer
        let len = try! FrameProtocol.input(buffer: &input)
        XCTAssertEqual(len, 14)
        
        let decoded = FrameProtocol.decode(buffer: &input)
        XCTAssertEqual(decoded, "SwiftLotus")
    }

    // MARK: - WebSocket Tests

    func testWebSocketFragmentedTextMessageIsDeliveredOnceWhenFinalFrameArrives() throws {
        let worker = SwiftLotus<WebSocketProtocol>(name: "WebSocketTest", uri: "websocket://127.0.0.1:0", enableSignalHandlers: false)
        let expectation = expectation(description: "fragmented websocket message")
        let receivedMessages = MessageRecorder()

        worker.onMessage = { _, frame in
            receivedMessages.append(frame.string)
            expectation.fulfill()
        }

        let channel = EmbeddedChannel(handler: LotusWebSocketHandler(worker: worker))
        let first = channel.allocator.buffer(string: "hello ")
        let second = channel.allocator.buffer(string: "world")

        try channel.writeInbound(WebSocketFrame(fin: false, opcode: .text, data: first))
        XCTAssertTrue(receivedMessages.messages.isEmpty)

        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .continuation, data: second))
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedMessages.messages, ["hello world"])
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }

    func testWebSocketFrameStringUsesReaderIndex() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(string: "xxhello")
        buffer.moveReaderIndex(forwardBy: 2)

        let frame = WebSocketFrameWrapper(opcode: .text, data: buffer, fin: true)

        XCTAssertEqual(frame.string, "hello")
    }
    
    // MARK: - Integration Test (Mock)
    
    func testEchoServerLogic() async throws {
        // We can't easily spawn a real server in unit tests due to port binding and async complexity in XCTest.
        // But we can test the worker logic if we mock the connection.
        let worker = SwiftLotus<TextProtocol>(name: "Test", uri: "tcp://127.0.0.1:0")
        XCTAssertEqual(worker.name, "Test")
    }
}
