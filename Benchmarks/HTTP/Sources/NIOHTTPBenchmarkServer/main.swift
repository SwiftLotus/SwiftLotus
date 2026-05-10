@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

func argumentValue(_ name: String, default defaultValue: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

final class BenchmarkHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var keepAlive = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            keepAlive = head.isKeepAlive
        case .body:
            break
        case .end:
            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "2")
            if keepAlive {
                headers.add(name: "Connection", value: "keep-alive")
            } else {
                headers.add(name: "Connection", value: "close")
            }

            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            let body = context.channel.allocator.buffer(string: "OK")

            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            if !keepAlive {
                context.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

@main
struct NIOHTTPBenchmarkServer {
    static func main() async throws {
        let host = argumentValue("--host", default: "127.0.0.1")
        let port = Int(argumentValue("--port", default: "8788")) ?? 8788
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withPipeliningAssistance: true,
                        withServerUpgrade: nil,
                        withErrorHandling: true
                    )
                    try channel.pipeline.syncOperations.addHandler(BenchmarkHTTPHandler())
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)

        let channel = try await bootstrap.bind(host: host, port: port).get()
        print("READY NIOHTTPBenchmarkServer http://\(host):\(port)")
        try await channel.closeFuture.get()
        try await group.shutdownGracefully()
    }
}
