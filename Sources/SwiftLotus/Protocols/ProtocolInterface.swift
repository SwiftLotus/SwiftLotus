import NIOCore

/// Defines how to handle the byte stream, including framing (splitting packets) and encoding/decoding.
/// Formerly LotusProtocol / NetProtocol.
public protocol ProtocolInterface {
    
    /// The type of message this protocol produces (e.g., String, HttpRequest)
    associatedtype Message: Sendable
    
    /// The type of data user sends (e.g., String, HttpResponse)
    associatedtype Response: Sendable
    
    // MARK: - Pipeline Configuration
    
    /// Add handlers to the channel pipeline.
    /// Default implementation adds LotusDecoder and LotusEncoder.
    static func addHandlers(pipeline: ChannelPipeline, worker: SwiftLotus<Self>)
    
    // MARK: - Framing & Coding (Optional if addHandlers is overridden)
    
    /// Check the buffer to see if it contains a complete package.
    /// - Returns: The length of the package if complete, or 0 if more data is needed.
    static func input(buffer: inout ByteBuffer) -> Int
    
    /// Decode the complete package into a high-level message.
    static func decode(buffer: inout ByteBuffer) -> Message
    
    /// Encode a message into bytes to be sent.
    static func encode(data: Response, allocator: ByteBufferAllocator) -> ByteBuffer
}

// Default implementation
public extension ProtocolInterface {
    static func addHandlers(pipeline: ChannelPipeline, worker: SwiftLotus<Self>) {
        let _ = pipeline.addHandlers([
            ByteToMessageHandler(LotusDecoder<Self>()),
            MessageToByteHandler(LotusEncoder<Self>()),
            LotusHandler(worker: worker)
        ])
    }
    
    static func input(buffer: inout ByteBuffer) -> Int { 0 }
}
