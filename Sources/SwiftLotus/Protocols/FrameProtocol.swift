import NIOCore

/// A protocol with a 4-byte length header (Big Endian) followed by the body.
public struct FrameProtocol: ProtocolInterface {
    
    public typealias Message = String
    public typealias Response = String
    
    public static func input(buffer: inout ByteBuffer) -> Int {
        // We need at least 4 bytes for the header
        if buffer.readableBytes < 4 {
            return 0
        }
        
        // Read length (without moving reader index yet)
        guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else {
            return 0
        }
        
        // Total package length = 4 (header) + body length
        let totalLength = 4 + Int(length)
        
        if buffer.readableBytes >= totalLength {
            return totalLength
        }
        
        return 0
    }
    
    public static func decode(buffer: inout ByteBuffer) -> String {
        // Move reader index past the 4-byte header
        buffer.moveReaderIndex(forwardBy: 4)
        
        // Read the body
        let bodyLength = buffer.readableBytes
        guard let string = buffer.readString(length: bodyLength) else {
            return ""
        }
        return string
    }
    
    public static func encode(data: String, allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: 4 + data.utf8.count)
        
        // Write length
        buffer.writeInteger(UInt32(data.utf8.count))
        
        // Write body
        buffer.writeString(data)
        
        return buffer
    }
}
