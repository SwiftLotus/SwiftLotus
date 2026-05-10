@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSL
import Foundation
@preconcurrency import NIOConcurrencyHelpers

/// A globally shared EventLoopGroup to prevent thread leaks in AsyncTcpConnection
public enum GlobalEventLoop {
    public static let sharedGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
}

/// AsyncTcpConnection allows establishing an asynchronous TCP connection to a remote server.
public final class AsyncTcpConnection<P: ProtocolInterface>: @unchecked Sendable {
    
    // MARK: - Configuration
    
    public let uri: String
    
    // MARK: - Callbacks
    
    private let lock = NIOLock()
    
    private var _onConnect: (@Sendable (Connection<P>) async -> Void)?
    public var onConnect: (@Sendable (Connection<P>) async -> Void)? {
        get { lock.withLock { _onConnect } }
        set { lock.withLock { _onConnect = newValue } }
    }
    
    private var _onMessage: (@Sendable (Connection<P>, P.Message) async -> Void)?
    public var onMessage: (@Sendable (Connection<P>, P.Message) async -> Void)? {
        get { lock.withLock { _onMessage } }
        set { lock.withLock { _onMessage = newValue } }
    }
    
    private var _onClose: (@Sendable (Connection<P>) async -> Void)?
    public var onClose: (@Sendable (Connection<P>) async -> Void)? {
        get { lock.withLock { _onClose } }
        set { lock.withLock { _onClose = newValue } }
    }
    
    private var _onError: (@Sendable (Error) async -> Void)?
    public var onError: (@Sendable (Error) async -> Void)? {
        get { lock.withLock { _onError } }
        set { lock.withLock { _onError = newValue } }
    }
    
    // MARK: - Internals
    
    private let group: EventLoopGroup
    private var host: String = ""
    private var port: Int = 0
    private var scheme: String = "tcp"
    private var sslContext: NIOSSLContext?
    private var configurationError: SwiftLotusError?
    
    public init(uri: String, sslContext: NIOSSLContext? = nil) {
        self.uri = uri
        self.sslContext = sslContext
        self.group = GlobalEventLoop.sharedGroup
        parseUri(uri)
    }
    
    private func parseUri(_ uri: String) {
        guard let url = URL(string: uri),
              let h = url.host,
              let p = url.port else {
            configurationError = .invalidURI(uri)
            return
        }
        self.host = h
        self.port = p
        self.scheme = url.scheme ?? "tcp"
    }
    
    public func connect() {
        Task {
            do {
                try await self._connect()
            } catch {
                if let onError = self.onError {
                    await onError(error)
                }
            }
        }
    }
    
    private func _connect() async throws {
        try validateConfiguration()

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .channelInitializer { channel in
                return channel.eventLoop.makeSucceededFuture(()).flatMap {
                    var handlers: [ChannelHandler] = []

                    if self.scheme == "ssl" || self.scheme == "wss" || self.sslContext != nil {
                        if let context = self.sslContext {
                            do {
                                let sslHandler = try NIOSSLClientHandler(context: context, serverHostname: self.host)
                                handlers.append(sslHandler)
                            } catch {
                                return channel.eventLoop.makeFailedFuture(error)
                            }
                        }
                    }

                    handlers.append(ByteToMessageHandler(LotusDecoder<P>()))
                    handlers.append(MessageToByteHandler(LotusEncoder<P>()))
                    handlers.append(LotusClientHandler(connection: self))

                    do {
                        try channel.pipeline.syncOperations.addHandlers(handlers)
                        return channel.eventLoop.makeSucceededFuture(())
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
            }
        
        let channel = try await bootstrap.connect(host: host, port: port).get()
        
        // Wait for close
        try await channel.closeFuture.get()
    }

    private func validateConfiguration() throws {
        if let configurationError {
            throw configurationError
        }

        if requiresTLS && sslContext == nil {
            throw SwiftLotusError.tlsContextRequired(scheme: scheme)
        }
    }

    private var requiresTLS: Bool {
        switch scheme.lowercased() {
        case "ssl", "tls", "https", "wss":
            return true
        default:
            return false
        }
    }
}

final class LotusClientHandler<P: ProtocolInterface>: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = P.Message // We assume symmetric protocol for now
    
    let client: AsyncTcpConnection<P>
    var connection: Connection<P>?
    
    init(connection: AsyncTcpConnection<P>) {
        self.client = connection
    }
    
    func channelActive(context: ChannelHandlerContext) {
        let conn = Connection<P>(channel: context.channel)
        self.connection = conn
        if let onConnect = client.onConnect {
            Task { await onConnect(conn) }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data)
        guard let conn = self.connection else { return }
        
        if let onMessage = client.onMessage {
            Task { await onMessage(conn, message) }
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        guard let conn = self.connection else { return }
        if let onClose = client.onClose {
            Task { await onClose(conn) }
        }
        self.connection = nil
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let onError = client.onError {
            Task { await onError(error) }
        }
        context.close(promise: nil)
    }
}
