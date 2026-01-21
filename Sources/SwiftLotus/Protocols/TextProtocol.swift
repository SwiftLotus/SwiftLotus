import NIOCore

/// A simple protocol that separates messages by newlines ("\n").
public struct TextProtocol: ProtocolInterface {
    
    public typealias Message = String
    public typealias Response = String
    
    public static func input(buffer: inout ByteBuffer) -> Int {
        if let newlineIndex = buffer.readableBytesView.firstIndex(of: 10) { // 10 is '\n'
            return newlineIndex - buffer.readerIndex + 1
        }
        return 0
    }
    
    public static func decode(buffer: inout ByteBuffer) -> String {
        let readableBytes = buffer.readableBytes
        guard let string = buffer.readString(length: readableBytes) else {
            return ""
        }
        return string.trimmingCharacters(in: .newlines)
    }
    
    public static func encode(data: String, allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(string: data)
        buffer.writeString("\n")
        return buffer
    }
}
