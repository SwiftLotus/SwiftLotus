@preconcurrency import NIOCore
@preconcurrency import NIOPosix

func argumentValue(_ name: String, default defaultValue: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

final class LineEchoHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var buffer = ByteBuffer()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)
        buffer.writeBuffer(&inbound)

        var wrote = false
        while let newlineIndex = buffer.readableBytesView.firstIndex(of: 10) {
            let length = newlineIndex - buffer.readerIndex + 1
            guard let frame = buffer.readSlice(length: length) else { break }
            context.write(wrapOutboundOut(frame), promise: nil)
            wrote = true
        }

        if wrote {
            context.flush()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

@main
struct NIOTCPBenchmarkServer {
    static func main() async throws {
        let host = argumentValue("--host", default: "127.0.0.1")
        let port = Int(argumentValue("--port", default: "8798")) ?? 8798
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(LineEchoHandler())
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)

        let channel = try await bootstrap.bind(host: host, port: port).get()
        print("READY NIOTCPBenchmarkServer tcp://\(host):\(port)")
        try await channel.closeFuture.get()
        try await group.shutdownGracefully()
    }
}
