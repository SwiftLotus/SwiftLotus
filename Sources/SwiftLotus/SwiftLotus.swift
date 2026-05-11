@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSL
import Logging
import Foundation
import Dispatch
@preconcurrency import NIOConcurrencyHelpers

/// The main worker class that manages the server and connection lifecycle.
/// Renamed from Lotus to SwiftLotus.
public final class SwiftLotus<P: ProtocolInterface>: @unchecked Sendable {
    
    // MARK: - Configuration
    
    public var name: String
    public var count: Int
    public let uri: String
    
    /// SSL Context for enabling TLS/SSL
    public var sslContext: NIOSSLContext?
    public var enableSignalHandlers: Bool

    /// Adds an NIO idle handler when set. The event is delivered to `onIdle`.
    public var idleTimeout: TimeAmount?

    /// Close a connection automatically after an idle event.
    public var closeIdleConnections: Bool = false

    /// Optional write-buffer watermarks for backpressure.
    public var writeBufferWaterMark: ChannelOptions.Types.WriteBufferWaterMark?
    
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

    private var _onMessageSync: (@Sendable (Connection<P>, P.Message) -> Void)?
    /// Synchronous fast path executed on the channel event loop. Keep this callback non-blocking.
    public var onMessageSync: (@Sendable (Connection<P>, P.Message) -> Void)? {
        get { lock.withLock { _onMessageSync } }
        set { lock.withLock { _onMessageSync = newValue } }
    }
    
    private var _onClose: (@Sendable (Connection<P>) async -> Void)?
    public var onClose: (@Sendable (Connection<P>) async -> Void)? {
        get { lock.withLock { _onClose } }
        set { lock.withLock { _onClose = newValue } }
    }

    private var _onError: (@Sendable (Connection<P>?, Error) async -> Void)?
    public var onError: (@Sendable (Connection<P>?, Error) async -> Void)? {
        get { lock.withLock { _onError } }
        set { lock.withLock { _onError = newValue } }
    }

    private var _onBufferFull: (@Sendable (Connection<P>) async -> Void)?
    public var onBufferFull: (@Sendable (Connection<P>) async -> Void)? {
        get { lock.withLock { _onBufferFull } }
        set { lock.withLock { _onBufferFull = newValue } }
    }

    private var _onBufferDrain: (@Sendable (Connection<P>) async -> Void)?
    public var onBufferDrain: (@Sendable (Connection<P>) async -> Void)? {
        get { lock.withLock { _onBufferDrain } }
        set { lock.withLock { _onBufferDrain = newValue } }
    }

    private var _onIdle: (@Sendable (Connection<P>, SwiftLotusIdleEvent) async -> Void)?
    public var onIdle: (@Sendable (Connection<P>, SwiftLotusIdleEvent) async -> Void)? {
        get { lock.withLock { _onIdle } }
        set { lock.withLock { _onIdle = newValue } }
    }

    private var _onWorkerStart: (@Sendable (SwiftLotus<P>) async -> Void)?
    public var onWorkerStart: (@Sendable (SwiftLotus<P>) async -> Void)? {
        get { lock.withLock { _onWorkerStart } }
        set { lock.withLock { _onWorkerStart = newValue } }
    }

    private var _onWorkerStop: (@Sendable (SwiftLotus<P>) async -> Void)?
    public var onWorkerStop: (@Sendable (SwiftLotus<P>) async -> Void)? {
        get { lock.withLock { _onWorkerStop } }
        set { lock.withLock { _onWorkerStop = newValue } }
    }
    
    // MARK: - Internals
    
    // Protect connections dictionary
    private let connectionsLock = NIOLock()
    private var _connections: [UUID: Connection<P>] = [:]

    /// User/group oriented connection registry for long-lived services.
    public let registry = ConnectionRegistry<P>()
    
    /// Global array of active connections to this worker
    public var connections: [UUID: Connection<P>] {
        get { connectionsLock.withLock { _connections } }
    }
    
    internal func _addConnection(_ conn: Connection<P>) {
        connectionsLock.withLock { _connections[conn.id] = conn }
        registry.add(conn)
    }
    
    internal func _removeConnection(_ conn: Connection<P>) {
        let _ = connectionsLock.withLock { _connections.removeValue(forKey: conn.id) }
        registry.remove(conn)
    }
    
    private let group: MultiThreadedEventLoopGroup
    private let logger = Logger(label: "com.swiftlotus.worker")
    private var host: String = "0.0.0.0"
    private var port: Int = 0
    private var scheme: String = "tcp"
    private var signalSources: [DispatchSourceSignal] = []
    private var configurationError: SwiftLotusError?
    private let lifecycleLock = NIOLock()
    private var serverChannel: Channel?
    private var didShutdownGroup = false
    private var isRunning = false
    private var startedAt: Date?
    
    // MARK: - Initialization
    
    public init(name: String = "SwiftLotus", count: Int = System.coreCount, uri: String, enableSignalHandlers: Bool = true) {
        self.name = name
        self.count = count
        self.uri = uri
        self.enableSignalHandlers = enableSignalHandlers
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: count)
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
    
    // MARK: - Runtime
    
    public func run() async throws {
        do {
            try validateConfiguration()
        } catch {
            try? await shutdownGroupOnce()
            throw error
        }

        if enableSignalHandlers {
            setupSignalHandler()
        }
        
        var bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                self.configureChildPipeline(channel)
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)

        if let writeBufferWaterMark {
            bootstrap = bootstrap.childChannelOption(ChannelOptions.writeBufferWaterMark, value: writeBufferWaterMark)
        }
        
        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            lifecycleLock.withLock {
                serverChannel = channel
                isRunning = true
                startedAt = Date()
            }
            print("SwiftLotus [\(name)] started listening on \(uri)")
            if let onWorkerStart {
                Task { await onWorkerStart(self) }
            }

            // Wait until the channel closes
            try await channel.closeFuture.get()
            lifecycleLock.withLock {
                isRunning = false
            }
            if let onWorkerStop {
                Task { await onWorkerStop(self) }
            }
            try await shutdownGroupOnce()
        } catch {
            lifecycleLock.withLock {
                isRunning = false
            }
            if let onError {
                Task { await onError(nil, error) }
            }
            try? await shutdownGroupOnce()
            throw error
        }
    }

    private func configureChildPipeline(_ channel: Channel) -> EventLoopFuture<Void> {
        do {
            if let context = sslContext {
                let sslHandler = NIOSSLServerHandler(context: context)
                try channel.pipeline.syncOperations.addHandler(sslHandler)
            }

            if let idleTimeout {
                try channel.pipeline.syncOperations.addHandler(IdleStateHandler(allTimeout: idleTimeout))
            }

            return P.addHandlers(pipeline: channel.pipeline, worker: self)
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
    }

    public func stop() async throws {
        let channel = lifecycleLock.withLock { serverChannel }
        if let channel {
            try await channel.close().get()
        }
        lifecycleLock.withLock {
            isRunning = false
        }
        try await shutdownGroupOnce()
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

    private func shutdownGroupOnce() async throws {
        let shouldShutdown = lifecycleLock.withLock {
            if didShutdownGroup {
                return false
            }
            didShutdownGroup = true
            return true
        }

        if shouldShutdown {
            try await group.shutdownGracefully()
        }
    }
    
    private func setupSignalHandler() {
        #if !os(Windows)
        self.signalSources = distinctSignalSources(for: [SIGINT, SIGTERM])
        for source in self.signalSources {
            source.setEventHandler {
                print("\nReceived signal, shutting down...")
                Task {
                    do {
                        try await self.stop()
                        exit(0)
                    } catch {
                        print("Error shutting down: \(error)")
                        exit(1)
                    }
                }
            }
            source.resume()
        }
        #else
        print("Signal handling is not supported on Windows. Use Ctrl+C to force quit.")
        #endif
    }
    
    #if !os(Windows)
    private func distinctSignalSources(for signals: [Int32]) -> [DispatchSourceSignal] {
        return signals.map { signal in
            let source = DispatchSource.makeSignalSource(signal: signal, queue: DispatchQueue.global())
            return source
        }
    }
    #endif

    public var status: SwiftLotusStatus {
        lifecycleLock.withLock {
            SwiftLotusStatus(
                name: name,
                uri: uri,
                threadCount: count,
                connectionCount: registry.connectionCount,
                isRunning: isRunning,
                startedAt: startedAt
            )
        }
    }

    public func bind(_ connection: Connection<P>, uid: String) {
        registry.bind(connection, uid: uid)
    }

    public func unbind(_ connection: Connection<P>) {
        registry.unbind(connection)
    }

    public func join(_ connection: Connection<P>, group: String) {
        registry.join(connection, group: group)
    }

    public func leave(_ connection: Connection<P>, group: String) {
        registry.leave(connection, group: group)
    }

    public func connections(forUid uid: String) -> [Connection<P>] {
        registry.connections(forUid: uid)
    }

    public func connections(inGroup group: String) -> [Connection<P>] {
        registry.connections(inGroup: group)
    }

    @discardableResult
    public func sendToUid(_ uid: String, _ data: P.Response) async throws -> Int {
        try await registry.send(toUid: uid, data)
    }

    @discardableResult
    public func sendToGroup(_ group: String, _ data: P.Response) async throws -> Int {
        try await registry.send(toGroup: group, data)
    }

    @discardableResult
    public func broadcast(_ data: P.Response) async throws -> Int {
        try await registry.broadcast(data)
    }

    internal func _handleWritabilityChanged(_ connection: Connection<P>) {
        if connection.isWritable {
            if let onBufferDrain {
                Task { await onBufferDrain(connection) }
            }
        } else if let onBufferFull {
            Task { await onBufferFull(connection) }
        }
    }

    internal func _handleIdleEvent(_ event: Any, connection: Connection<P>, context: ChannelHandlerContext) {
        guard let nioEvent = event as? IdleStateHandler.IdleStateEvent,
              let idleEvent = SwiftLotusIdleEvent(nioEvent) else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        if let onIdle {
            Task { await onIdle(connection, idleEvent) }
        }

        if closeIdleConnections {
            context.close(promise: nil)
        }
    }

    internal func _handleError(_ error: Error, connection: Connection<P>?) {
        if let onError {
            Task { await onError(connection, error) }
        }
    }
}

// MARK: - Handlers

final class LotusDecoder<P: ProtocolInterface>: ByteToMessageDecoder {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = P.Message
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        let pkgLen = try P.input(buffer: &buffer)
        if pkgLen == 0 { return .needMoreData }
        
        if pkgLen > 0 {
            if pkgLen > P.maxPackageSize {
                throw SwiftLotusError.payloadTooLarge(maximum: P.maxPackageSize)
            }
            guard var pkgBuffer = buffer.readSlice(length: pkgLen) else { return .needMoreData }
            let message = P.decode(buffer: &pkgBuffer)
            context.fireChannelRead(self.wrapInboundOut(message))
            return .continue
        }
        return .needMoreData
    }
}

final class LotusEncoder<P: ProtocolInterface>: MessageToByteEncoder {
    typealias OutboundIn = P.Response
    
    func encode(data: P.Response, out: inout ByteBuffer) throws {
        let buffer = P.encode(data: data, allocator: ByteBufferAllocator())
        var mutableBuffer = buffer
        out.writeBuffer(&mutableBuffer)
    }
}

final class LotusHandler<P: ProtocolInterface>: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = P.Message
    typealias OutboundOut = P.Response
    
    let worker: SwiftLotus<P>
    var connection: Connection<P>?
    
    init(worker: SwiftLotus<P>) {
        self.worker = worker
    }
    
    func channelActive(context: ChannelHandlerContext) {
        let conn = Connection<P>(channel: context.channel)
        self.connection = conn
        
        worker._addConnection(conn)
        
        if let onConnect = worker.onConnect {
            Task { await onConnect(conn) }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data)
        guard let conn = self.connection else { return }
        if let onMessageSync = worker.onMessageSync {
            onMessageSync(conn, message)
        } else if let onMessage = worker.onMessage {
            Task { await onMessage(conn, message) }
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if let conn = connection {
            worker._handleWritabilityChanged(conn)
        }
        context.fireChannelWritabilityChanged()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let conn = connection {
            worker._handleIdleEvent(event, connection: conn, context: context)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        guard let conn = self.connection else { return }
        
        worker._removeConnection(conn)
        
        if let onClose = worker.onClose {
            Task { await onClose(conn) }
        }
        self.connection = nil
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        worker._handleError(error, connection: connection)
        context.close(promise: nil)
    }
}
