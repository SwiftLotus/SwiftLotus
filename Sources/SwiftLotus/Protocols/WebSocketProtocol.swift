import NIOCore
import NIOHTTP1
import NIOWebSocket

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
    public static func input(buffer: inout ByteBuffer) -> Int { 0 }
    public static func decode(buffer: inout ByteBuffer) -> WebSocketFrameWrapper { fatalError() }
    public static func encode(data: WebSocketFrameWrapper, allocator: ByteBufferAllocator) -> ByteBuffer { fatalError() }
    
    public static func addHandlers(pipeline: ChannelPipeline, worker: SwiftLotus<Self>) {
        
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                channel.pipeline.addHandler(LotusWebSocketHandler(worker: worker))
            }
        )
        
        let upgradeConfig = (
            upgraders: [upgrader],
            completionHandler: { (context: ChannelHandlerContext) in
                // Remove HTTP handlers after upgrade? 
                // NIO does this automatically usually.
            }
        )
        
        // Use withServerUpgrade
        let _ = pipeline.configureHTTPServerPipeline(
            withPipeliningAssistance: true,
            withServerUpgrade: upgradeConfig,
            withErrorHandling: true
        )
    }
}

/// The actual WebSocket Handler
final class LotusWebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    let worker: SwiftLotus<WebSocketProtocol>
    var connection: Connection<WebSocketProtocol>?
    
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
            let wrapper = WebSocketFrameWrapper(opcode: frame.opcode, data: frame.data, fin: frame.fin)
            guard let conn = self.connection else { return }
            if let onMessage = worker.onMessage {
                Task { await onMessage(conn, wrapper) }
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
    
    func channelInactive(context: ChannelHandlerContext) {
        guard let conn = self.connection else { return }
        if let onClose = worker.onClose {
            Task { await onClose(conn) }
        }
        self.connection = nil
    }
}

// Connection Extension for easy sending
extension Connection where P == WebSocketProtocol {
    public func send(_ text: String) async throws {
        let buffer = channel.allocator.buffer(string: text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        try await channel.writeAndFlush(frame)
    }
    
    public func send(_ response: WebSocketFrameWrapper) async throws {
        let frame = WebSocketFrame(fin: response.fin, opcode: response.opcode, data: response.data)
        try await channel.writeAndFlush(frame)
    }
}
