import SwiftLotus
import NIOCore
import MySQLNIO

public enum SwiftLotusMySQL {
    public static func connect(hostname: String = "127.0.0.1", port: Int = 3306, username: String, password: String?, database: String) async throws -> MySQLConnection {
        let address = try SocketAddress(ipAddress: hostname, port: port)
        return try await MySQLConnection.connect(
            to: address,
            username: username,
            database: database,
            password: password,
            tlsConfiguration: nil,
            on: GlobalEventLoop.sharedGroup.next()
        ).get()
    }
}
