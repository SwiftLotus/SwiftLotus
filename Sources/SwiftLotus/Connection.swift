import NIOCore
import NIOPosix
import Foundation

/// A wrapper around a network connection (Channel).
/// Generic over P: ProtocolInterface to ensure type-safe sending.
public final class Connection<P: ProtocolInterface>: Sendable, Identifiable {
    
    public let id: UUID
    let channel: Channel
    
    public var remoteAddress: SocketAddress? {
        channel.remoteAddress
    }
    
    init(channel: Channel) {
        self.id = UUID()
        self.channel = channel
    }
    
    /// Send data to the client.
    /// - Parameter data: The data to send (type defined by Protocol).
    public func send(_ data: P.Response) async throws {
        try await channel.writeAndFlush(data)
    }
    
    /// Close the connection
    public func close() async throws {
        try await channel.close()
    }
}

extension Connection: Hashable {
    public static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
