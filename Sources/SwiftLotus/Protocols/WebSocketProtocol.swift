@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket

/// A wrapper to conform to Sendable for WebSocket Frames
public struct WebSocketFrameWrapper: Sendable {
    public let opcode: WebSocketOpcode
    public let data: ByteBuffer
    public let fin: Bool
    
    public var string: String {
        return data.getString(at: 0, length: data.readableBytes) ?? ""
    }
}

/// WebSocket Protocol implementation using NIOWebSocket
public struct WebSocketProtocol: ProtocolInterface {
    
    public typealias Message = WebSocketFrameWrapper
    public typealias Response = WebSocketFrameWrapper
    
    // Unused
    public static func input(buffer: inout ByteBuffer) throws -> Int { 0 }
    public static func decode(buffer: inout ByteBuffer) -> WebSocketFrameWrapper { fatalError() }
    public static func encode(data: WebSocketFrameWrapper, allocator: ByteBufferAllocator) -> ByteBuffer { fatalError() }
    
    public static func addHandlers(pipeline: ChannelPipeline, worker: SwiftLotus<Self>) -> EventLoopFuture<Void> {
        
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: maxPackageSize,
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                channel.pipeline.addHandler(LotusWebSocketHandler(worker: worker))
            }
        )
        
        let upgradeConfig: NIOHTTPServerUpgradeConfiguration = (
            upgraders: [upgrader],
            completionHandler: { @Sendable (context: ChannelHandlerContext) in
                // Remove HTTP handlers after upgrade
            }
        )
        
        // Use withServerUpgrade
        do {
            try pipeline.syncOperations.configureHTTPServerPipeline(
                withPipeliningAssistance: true,
                withServerUpgrade: upgradeConfig,
                withErrorHandling: true
            )
            return pipeline.eventLoop.makeSucceededFuture(())
        } catch {
            return pipeline.eventLoop.makeFailedFuture(error)
        }
    }
}

/// The actual WebSocket Handler
final class LotusWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    let worker: SwiftLotus<WebSocketProtocol>
    var connection: Connection<WebSocketProtocol>?
    private var fragmentedOpcode: WebSocketOpcode?
    private var fragmentedData: ByteBuffer?
    private var fragmentedBytes = 0
    
    init(worker: SwiftLotus<WebSocketProtocol>) {
        self.worker = worker
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // This might be called when TCP connects, but we only care after Upgrade?
        // Actually, for WebSocket, 'onConnect' usually means handshake done.
        // In NIO, this handler is added *after* upgrade.
        // So handlerAdded is the right place.
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        let conn = Connection<WebSocketProtocol>(channel: context.channel)
        self.connection = conn
        guard worker._registerConnection(conn, context: context) else { return }
        
        if let onConnect = worker.onConnect {
            Task { await onConnect(conn) }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        
        switch frame.opcode {
        case .connectionClose:
            // Handle close
            context.close(promise: nil)
        case .text, .binary:
            if frame.fin {
                fireMessage(frame.opcode, data: frame.data)
            } else {
                fragmentedOpcode = frame.opcode
                fragmentedData = frame.data
                fragmentedBytes = frame.data.readableBytes
                closeIfFragmentedMessageIsTooLarge(context: context)
            }
        case .continuation:
            guard fragmentedOpcode != nil, var existingData = fragmentedData else {
                context.close(promise: nil)
                return
            }
            var data = frame.data
            existingData.writeBuffer(&data)
            fragmentedData = existingData
            fragmentedBytes += frame.data.readableBytes

            guard !closeIfFragmentedMessageIsTooLarge(context: context) else { return }

            if frame.fin {
                let opcode = fragmentedOpcode!
                let completeData = existingData
                clearFragmentedMessage()
                fireMessage(opcode, data: completeData)
            }
        case .ping:
            // Auto pong
            let frameData = frame.data
            let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
            context.writeAndFlush(self.wrapOutboundOut(pongFrame), promise: nil)
        default:
            break
        }
    }

    private func fireMessage(_ opcode: WebSocketOpcode, data: ByteBuffer) {
        let wrapper = WebSocketFrameWrapper(opcode: opcode, data: data, fin: true)
        guard let conn = self.connection else { return }
        if let onMessageSync = worker.onMessageSync {
            onMessageSync(conn, wrapper)
        } else if let onMessage = worker.onMessage {
            Task { await onMessage(conn, wrapper) }
        }
    }

    @discardableResult
    private func closeIfFragmentedMessageIsTooLarge(context: ChannelHandlerContext) -> Bool {
        if fragmentedBytes > WebSocketProtocol.maxPackageSize {
            clearFragmentedMessage()
            context.close(promise: nil)
            return true
        }
        return false
    }

    private func clearFragmentedMessage() {
        fragmentedOpcode = nil
        fragmentedData = nil
        fragmentedBytes = 0
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
        worker.writeRuntimeStatus()
        
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

// Connection Extension for easy sending
extension Connection where P == WebSocketProtocol {
    public func send(_ text: String) async throws {
        try await writeWebSocketText(text).get()
    }

    @discardableResult
    public func writeWebSocketText(_ text: String) -> EventLoopFuture<Void> {
        let buffer = channel.allocator.buffer(string: text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        return channel.writeAndFlush(frame)
    }
    
    public func send(_ response: WebSocketFrameWrapper) async throws {
        try await writeWebSocketResponse(response).get()
    }

    @discardableResult
    public func writeWebSocketResponse(_ response: WebSocketFrameWrapper) -> EventLoopFuture<Void> {
        let frame = WebSocketFrame(fin: response.fin, opcode: response.opcode, data: response.data)
        return channel.writeAndFlush(frame)
    }
}
