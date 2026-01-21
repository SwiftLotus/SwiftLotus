import NIOCore
import NIOHTTP1
import Foundation

/// A wrapper to conform to Sendable for HTTP Requests
public struct HttpRequest: Sendable {
    public let head: HTTPRequestHead
    public let body: String?
    
    public var uri: String { head.uri }
    public var method: HTTPMethod { head.method }
    public var headers: HTTPHeaders { head.headers }
    
    // MARK: - Helpers
    
    /// Get query parameters
    public var query: [String: String] {
        guard let url = URL(string: "http://localhost\(uri)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return [:]
        }
        var dict: [String: String] = [:]
        for item in items {
            dict[item.name] = item.value ?? ""
        }
        return dict
    }
    
    /// Get cookies
    public var cookies: [String: String] {
        guard let cookieHeader = headers["Cookie"].first else { return [:] }
        var dict: [String: String] = [:]
        let items = cookieHeader.split(separator: ";")
        for item in items {
            let parts = item.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                dict[key] = value
            }
        }
        return dict
    }
    
    /// Get Session ID (from PHPSESSID or LOTUSSESSID)
    public var sessionId: String? {
        return cookies["LOTUSSESSID"]
    }
    
    /// Get Session Data (Async)
    public func session() async -> [String: String] {
        guard let sid = sessionId else { return [:] }
        return await SessionManager.shared.get(sid)
    }
}

/// A wrapper to conform to Sendable for HTTP Responses
public struct HttpResponse: Sendable {
    public let status: HTTPResponseStatus
    public let body: String
    public var headers: HTTPHeaders
    
    public init(status: HTTPResponseStatus = .ok, body: String = "", headers: HTTPHeaders = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
    
    /// Set a cookie
    public mutating func setCookie(name: String, value: String, path: String = "/", maxAge: Int? = nil) {
        var cookie = "\(name)=\(value); Path=\(path)"
        if let age = maxAge {
            cookie += "; Max-Age=\(age)"
        }
        headers.add(name: "Set-Cookie", value: cookie)
    }
}

/// HTTP Protocol implementation using NIOHTTP1
public struct HttpProtocol: ProtocolInterface {
    
    public typealias Message = HttpRequest
    public typealias Response = HttpResponse
    
    public static func addHandlers(pipeline: ChannelPipeline, worker: SwiftLotus<Self>) {
        let _ = pipeline.configureHTTPServerPipeline(position: .first, withPipeliningAssistance: true, withServerUpgrade: nil, withErrorHandling: true).flatMap {
            pipeline.addHandler(LotusHttpHandler(worker: worker))
        }
    }
    
    // Unused because we override addHandlers
    public static func input(buffer: inout ByteBuffer) -> Int { 0 }
    public static func decode(buffer: inout ByteBuffer) -> HttpRequest { fatalError() }
    public static func encode(data: HttpResponse, allocator: ByteBufferAllocator) -> ByteBuffer { fatalError() }
}

/// Handler that bridges NIOHTTP1 events to Lotus events
final class LotusHttpHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    let worker: SwiftLotus<HttpProtocol>
    var connection: Connection<HttpProtocol>?
    
    // State to accumulate body
    var requestHead: HTTPRequestHead?
    var requestBody: String?
    
    init(worker: SwiftLotus<HttpProtocol>) {
        self.worker = worker
    }
    
    func channelActive(context: ChannelHandlerContext) {
        let conn = Connection<HttpProtocol>(channel: context.channel)
        self.connection = conn
        
        if let onConnect = worker.onConnect {
            Task { await onConnect(conn) }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        
        switch part {
        case .head(let head):
            self.requestHead = head
            self.requestBody = ""
            
        case .body(let buffer):
            let string = buffer.getString(at: 0, length: buffer.readableBytes) ?? ""
            self.requestBody?.append(string)
            
        case .end(_):
            guard let head = requestHead else { return }
            let request = HttpRequest(head: head, body: requestBody)
            
            guard let conn = self.connection else { return }
            
            if let onMessage = worker.onMessage {
                Task {
                    await onMessage(conn, request)
                }
            }
            
            // Clean up
            self.requestHead = nil
            self.requestBody = nil
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        guard let conn = self.connection else { return }
        if let onClose = worker.onClose {
            Task { await onClose(conn) }
        }
        self.connection = nil
    }
}

// Extend Connection to support easier HTTP sending
extension Connection where P == HttpProtocol {
    public func send(_ response: HttpResponse) async throws {
        // Send Head
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: response.status, headers: response.headers)
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        
        // Send Body
        let buffer = channel.allocator.buffer(string: response.body)
        channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        
        // Send End
        try await channel.writeAndFlush(HTTPServerResponsePart.end(nil))
    }
    
    // Helper to send simple string
    public func send(_ body: String) async throws {
        try await send(HttpResponse(body: body))
    }
}
