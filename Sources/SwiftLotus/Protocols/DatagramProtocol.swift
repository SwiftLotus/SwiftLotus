@preconcurrency import NIOCore

public struct DatagramTextProtocol: ProtocolInterface {
    public typealias Message = String
    public typealias Response = String

    public static func input(buffer: inout ByteBuffer) throws -> Int {
        buffer.readableBytes
    }

    public static func decode(buffer: inout ByteBuffer) -> String {
        buffer.readString(length: buffer.readableBytes) ?? ""
    }

    public static func encode(data: String, allocator: ByteBufferAllocator) -> ByteBuffer {
        allocator.buffer(string: data)
    }
}
