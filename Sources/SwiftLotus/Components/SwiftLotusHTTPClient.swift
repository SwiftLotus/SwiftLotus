@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOHTTP1
@preconcurrency import NIOSSL
import Foundation

public struct SwiftLotusHTTPRequest: Sendable {
    public let method: HTTPMethod
    public let url: String
    public var headers: HTTPHeaders
    public var body: String?

    public let host: String
    public let port: Int
    public let pathWithQuery: String
    public let isTLS: Bool

    public init(method: HTTPMethod = .GET, url: String, headers: HTTPHeaders = HTTPHeaders(), body: String? = nil) throws {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host else {
            throw SwiftLotusError.invalidURI(url)
        }

        let isTLS = scheme == "https"
        guard scheme == "http" || isTLS else {
            throw SwiftLotusError.invalidURI(url)
        }

        let path = components.path.isEmpty ? "/" : components.path
        let pathWithQuery = components.query.map { "\(path)?\($0)" } ?? path

        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.host = host
        self.port = components.port ?? (isTLS ? 443 : 80)
        self.pathWithQuery = pathWithQuery
        self.isTLS = isTLS
    }
}

public struct SwiftLotusHTTPClientResponse: Sendable, Equatable {
    public let status: HTTPResponseStatus
    public let headers: HTTPHeaders
    public let body: String
}

public final class SwiftLotusHTTPClient: @unchecked Sendable {
    private let group: EventLoopGroup
    private let sslContext: NIOSSLContext?

    public init(group: EventLoopGroup = GlobalEventLoop.sharedGroup, sslContext: NIOSSLContext? = nil) {
        self.group = group
        self.sslContext = sslContext
    }

    public func get(_ url: String, headers: HTTPHeaders = HTTPHeaders()) async throws -> SwiftLotusHTTPClientResponse {
        try await request(SwiftLotusHTTPRequest(method: .GET, url: url, headers: headers))
    }

    public func post(_ url: String, headers: HTTPHeaders = HTTPHeaders(), body: String) async throws -> SwiftLotusHTTPClientResponse {
        try await request(SwiftLotusHTTPRequest(method: .POST, url: url, headers: headers, body: body))
    }

    public func request(_ request: SwiftLotusHTTPRequest) async throws -> SwiftLotusHTTPClientResponse {
        let eventLoop = group.next()
        let promise = eventLoop.makePromise(of: SwiftLotusHTTPClientResponse.self)

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                var futures: [EventLoopFuture<Void>] = []

                if request.isTLS {
                    do {
                        let context = try self.sslContext ?? NIOSSLContext(configuration: .makeClientConfiguration())
                        let sslHandler = try NIOSSLClientHandler(context: context, serverHostname: request.host)
                        try channel.pipeline.syncOperations.addHandler(sslHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }

                futures.append(channel.pipeline.addHTTPClientHandlers())
                futures.append(channel.pipeline.addHandler(SwiftLotusHTTPClientHandler(request: request, promise: promise)))
                return EventLoopFuture.andAllSucceed(futures, on: channel.eventLoop)
            }

        do {
            _ = try await bootstrap.connect(host: request.host, port: request.port).get()
        } catch {
            promise.fail(error)
            throw error
        }

        return try await promise.futureResult.get()
    }
}

private final class SwiftLotusHTTPClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let request: SwiftLotusHTTPRequest
    private let promise: EventLoopPromise<SwiftLotusHTTPClientResponse>
    private var responseHead: HTTPResponseHead?
    private var body = ByteBuffer()

    init(request: SwiftLotusHTTPRequest, promise: EventLoopPromise<SwiftLotusHTTPClientResponse>) {
        self.request = request
        self.promise = promise
    }

    func channelActive(context: ChannelHandlerContext) {
        var headers = request.headers
        if !headers.contains(name: "Host") {
            let defaultPort = request.isTLS ? 443 : 80
            let hostHeader = request.port == defaultPort ? request.host : "\(request.host):\(request.port)"
            headers.add(name: "Host", value: hostHeader)
        }
        if let body = request.body, !headers.contains(name: "Content-Length") {
            headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        }

        let head = HTTPRequestHead(version: .http1_1, method: request.method, uri: request.pathWithQuery, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        if let body = request.body {
            let buffer = context.channel.allocator.buffer(string: body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            responseHead = head
        case .body(var buffer):
            body.writeBuffer(&buffer)
        case .end:
            guard let head = responseHead else {
                promise.fail(SwiftLotusError.invalidURI("HTTP response ended without a head"))
                context.close(promise: nil)
                return
            }
            let text = body.getString(at: body.readerIndex, length: body.readableBytes) ?? ""
            promise.succeed(SwiftLotusHTTPClientResponse(status: head.status, headers: head.headers, body: text))
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }
}
