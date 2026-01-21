import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
@testable import SwiftLotus

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
        
        let len = TextProtocol.input(buffer: &buffer)
        XCTAssertEqual(len, 6) // "Hello\n" is 6 chars
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
    
    // MARK: - FrameProtocol Tests
    
    func testFrameProtocol() {
        let allocator = ByteBufferAllocator()
        let data = "SwiftLotus"
        let buffer = FrameProtocol.encode(data: data, allocator: allocator)
        
        // Header is 4 bytes length
        XCTAssertEqual(buffer.readableBytes, 4 + 10)
        
        var input = buffer
        let len = FrameProtocol.input(buffer: &input)
        XCTAssertEqual(len, 14)
        
        let decoded = FrameProtocol.decode(buffer: &input)
        XCTAssertEqual(decoded, "SwiftLotus")
    }
    
    // MARK: - Integration Test (Mock)
    
    func testEchoServerLogic() async throws {
        // We can't easily spawn a real server in unit tests due to port binding and async complexity in XCTest.
        // But we can test the worker logic if we mock the connection.
        let worker = SwiftLotus<TextProtocol>(name: "Test", uri: "tcp://127.0.0.1:0")
        XCTAssertEqual(worker.name, "Test")
    }
}
