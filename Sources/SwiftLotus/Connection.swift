import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
import Foundation

/// A wrapper around a network connection (Channel).
/// Generic over P: ProtocolInterface to ensure type-safe sending.
public final class Connection<P: ProtocolInterface>: @unchecked Sendable, Identifiable {
    
    public let id: UUID
    let channel: Channel
    let metrics: SwiftLotusMetrics?
    private let stateLock = NIOLock()
    private var _isReadPaused = false
    private var _isAuthenticated = false
    
    public var remoteAddress: SocketAddress? {
        channel.remoteAddress
    }

    public var isActive: Bool {
        channel.isActive
    }

    public var isWritable: Bool {
        channel.isWritable
    }

    public var eventLoop: EventLoop {
        channel.eventLoop
    }

    public var isReadPaused: Bool {
        stateLock.withLock { _isReadPaused }
    }

    public var isAuthenticated: Bool {
        stateLock.withLock { _isAuthenticated }
    }
    
    init(channel: Channel, metrics: SwiftLotusMetrics? = nil) {
        self.id = UUID()
        self.channel = channel
        self.metrics = metrics
    }
    
    /// Send data to the client.
    /// - Parameter data: The data to send (type defined by Protocol).
    public func send(_ data: P.Response) async throws {
        try await writeProtocolResponse(data).get()
    }

    /// Write data and return the underlying EventLoopFuture for event-loop fast paths.
    @discardableResult
    public func writeProtocolResponse(_ data: P.Response) -> EventLoopFuture<Void> {
        let future = channel.writeAndFlush(data)
        future.whenSuccess { [metrics] in
            metrics?.incrementCounter("messages.sent")
        }
        return future
    }
    
    /// Close the connection
    public func close() async throws {
        try await closeFuture().get()
    }

    /// Close the connection and return the underlying EventLoopFuture.
    @discardableResult
    public func closeFuture() -> EventLoopFuture<Void> {
        channel.close()
    }

    /// Temporarily stop automatic reads from this connection.
    @discardableResult
    public func pauseRead() -> EventLoopFuture<Void> {
        let future = channel.setOption(ChannelOptions.autoRead, value: false)
        future.whenSuccess { [weak self] in
            guard let self else { return }
            self.stateLock.withLock {
                self._isReadPaused = true
            }
        }
        return future
    }

    /// Resume automatic reads after `pauseRead()`.
    @discardableResult
    public func resumeRead() -> EventLoopFuture<Void> {
        let future = channel.setOption(ChannelOptions.autoRead, value: true)
        future.whenSuccess { [weak self] in
            guard let self else { return }
            self.stateLock.withLock {
                self._isReadPaused = false
            }
        }
        return future
    }

    public func markAuthenticated() {
        stateLock.withLock {
            _isAuthenticated = true
        }
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
