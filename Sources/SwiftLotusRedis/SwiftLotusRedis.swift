import SwiftLotus
import NIOCore
import RediStack

public enum SwiftLotusRedis {
    nonisolated(unsafe) public static var pool: RedisConnectionPool!
    
    public static func setup(hostname: String = "127.0.0.1", port: Int = 6379, maxConnectionsPerLoop: Int = 10) throws {
        let address = try SocketAddress(ipAddress: hostname, port: port)
        
        let config = RedisConnectionPool.Configuration(
            initialServerConnectionAddresses: [address],
            maximumConnectionCount: .maximumActiveConnections(maxConnectionsPerLoop),
            connectionFactoryConfiguration: .init()
        )
        self.pool = RedisConnectionPool(
            configuration: config,
            boundEventLoop: GlobalEventLoop.sharedGroup.next()
        )
    }
}
