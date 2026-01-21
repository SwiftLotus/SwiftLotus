import NIOCore
import NIOPosix
import NIOSSL
import Logging
import Foundation
import Dispatch

/// The main worker class that manages the server and connection lifecycle.
/// Renamed from Lotus to SwiftLotus.
public final class SwiftLotus<P: ProtocolInterface>: @unchecked Sendable {
    
    // MARK: - Configuration
    
    public var name: String
    public var count: Int = System.coreCount
    public let uri: String
    
    /// SSL Context for enabling TLS/SSL
    public var sslContext: NIOSSLContext?
    
    // MARK: - Callbacks
    
    public var onConnect: (@Sendable (Connection<P>) async -> Void)?
    public var onMessage: (@Sendable (Connection<P>, P.Message) async -> Void)?
    public var onClose: (@Sendable (Connection<P>) async -> Void)?
    
    // MARK: - Internals
    
    private let group: MultiThreadedEventLoopGroup
    private let logger = Logger(label: "com.swiftlotus.worker")
    private var host: String = "0.0.0.0"
    private var port: Int = 0
    private var scheme: String = "tcp"
    
    // MARK: - Initialization
    
    public init(name: String = "SwiftLotus", uri: String) {
        self.name = name
        self.uri = uri
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        parseUri(uri)
    }
    
    private func parseUri(_ uri: String) {
        guard let url = URL(string: uri),
              let h = url.host,
              let p = url.port else {
            logger.error("Invalid URI format: \(uri)")
            return
        }
        self.host = h
        self.port = p
        self.scheme = url.scheme ?? "tcp"
    }
    
    // MARK: - Runtime
    
    public func run() async throws {
        setupSignalHandler()
        
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // Add SSL Handler if context exists
                if let context = self.sslContext {
                    do {
                         let sslHandler = NIOSSLServerHandler(context: context)
                         _ = channel.pipeline.addHandler(sslHandler)
                    } 
                }
                
                // Delegate to Protocol to configure pipeline
                P.addHandlers(pipeline: channel.pipeline, worker: self)
                return channel.eventLoop.makeSucceededFuture(())
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
        
        let channel = try await bootstrap.bind(host: host, port: port).get()
        print("SwiftLotus [\(name)] started listening on \(uri)")
        
        // Wait until the channel closes
        try await channel.closeFuture.get()
    }
    
    private func setupSignalHandler() {
        #if !os(Windows)
        let signalQueue = distinctSignalSources(for: [SIGINT, SIGTERM])
        for source in signalQueue {
            source.setEventHandler {
                print("\nReceived signal, shutting down...")
                Task {
                    do {
                        try await self.group.shutdownGracefully()
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
}

// MARK: - Handlers

final class LotusDecoder<P: ProtocolInterface>: ByteToMessageDecoder {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = P.Message
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        let pkgLen = P.input(buffer: &buffer)
        if pkgLen == 0 { return .needMoreData }
        
        if pkgLen > 0 {
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

final class LotusHandler<P: ProtocolInterface>: ChannelInboundHandler {
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
        if let onConnect = worker.onConnect {
            Task { await onConnect(conn) }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data)
        guard let conn = self.connection else { return }
        if let onMessage = worker.onMessage {
            Task { await onMessage(conn, message) }
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        guard let conn = self.connection else { return }
        if let onClose = worker.onClose {
            Task { await onClose(conn) }
        }
        self.connection = nil
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
