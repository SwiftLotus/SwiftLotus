@preconcurrency import NIOCore
@preconcurrency import NIOPosix
import Foundation
@preconcurrency import NIOConcurrencyHelpers

public final class SwiftLotusUDP<P: ProtocolInterface>: @unchecked Sendable {
    public var name: String
    public let uri: String
    public private(set) var host: String
    public private(set) var port: Int
    public var onMessage: (@Sendable (SocketAddress, P.Message, SwiftLotusUDP<P>) async -> Void)?

    private let group: MultiThreadedEventLoopGroup
    private let threadCount: Int
    private let lock = NIOLock()
    private var channel: Channel?
    private var isRunning = false
    private var startedAt: Date?

    public init(name: String = "SwiftLotusUDP", uri: String, threadCount: Int = System.coreCount) {
        self.name = name
        self.uri = uri
        let parsed = Self.parseURI(uri)
        self.host = parsed.host
        self.port = parsed.port
        self.threadCount = threadCount
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
    }

    public var status: SwiftLotusStatus {
        lock.withLock {
            SwiftLotusStatus(
                name: name,
                uri: uri,
                threadCount: threadCount,
                connectionCount: 0,
                isRunning: isRunning,
                startedAt: startedAt
            )
        }
    }

    public func run() async throws {
        let bootstrap = DatagramBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(SwiftLotusUDPHandler(server: self))
            }

        let channel = try await bootstrap.bind(host: host, port: port).get()
        lock.withLock {
            self.channel = channel
            self.isRunning = true
            self.startedAt = Date()
        }
        try await channel.closeFuture.get()
        try await group.shutdownGracefully()
    }

    public func stop() async throws {
        let channel = lock.withLock { self.channel }
        if let channel {
            try await channel.close().get()
        }
        lock.withLock {
            isRunning = false
        }
        try await group.shutdownGracefully()
    }

    @discardableResult
    public func send(_ data: P.Response, to remoteAddress: SocketAddress) -> EventLoopFuture<Void> {
        guard let channel = lock.withLock({ self.channel }) else {
            return group.next().makeFailedFuture(ChannelError.ioOnClosedChannel)
        }
        let buffer = P.encode(data: data, allocator: channel.allocator)
        let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)
        return channel.writeAndFlush(envelope)
    }

    private static func parseURI(_ uri: String) -> (host: String, port: Int) {
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port else {
            return ("127.0.0.1", 0)
        }
        return (host, port)
    }
}

private final class SwiftLotusUDPHandler<P: ProtocolInterface>: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let server: SwiftLotusUDP<P>

    init(server: SwiftLotusUDP<P>) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        let message = P.decode(buffer: &buffer)

        if let onMessage = server.onMessage {
            Task {
                await onMessage(envelope.remoteAddress, message, server)
            }
        }
    }
}
