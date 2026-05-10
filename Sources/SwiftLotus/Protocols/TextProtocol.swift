import NIOCore

/// A simple protocol that separates messages by newlines ("\n").
public struct TextProtocol: ProtocolInterface {
    
    public typealias Message = String
    public typealias Response = String
    
    public static func input(buffer: inout ByteBuffer) throws -> Int {
        if buffer.readableBytes > maxPackageSize {
            throw SwiftLotusError.payloadTooLarge(maximum: maxPackageSize)
        }

        if let newlineIndex = buffer.readableBytesView.firstIndex(of: 10) { // 10 is '\n'
            let packageLength = newlineIndex - buffer.readerIndex + 1
            if packageLength > maxPackageSize {
                throw SwiftLotusError.payloadTooLarge(maximum: maxPackageSize)
            }
            return packageLength
        }
        return 0
    }
    
    public static func decode(buffer: inout ByteBuffer) -> String {
        let readableBytes = buffer.readableBytes
        guard let string = buffer.readString(length: readableBytes) else {
            return ""
        }
        var message = string
        if message.utf8.last == 10 {
            message.removeLast()
            if message.utf8.last == 13 {
                message.removeLast()
            }
        }
        return message
    }
    
    public static func encode(data: String, allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(string: data)
        buffer.writeString("\n")
        return buffer
    }
}
