import SwiftLotus
import NIOCore
import PostgresNIO
import Logging

public enum SwiftLotusPostgres {
    public static func connect(hostname: String = "127.0.0.1", port: Int = 5432, username: String, password: String?, database: String) async throws -> PostgresConnection {
        let config = PostgresConnection.Configuration(
            connection: .init(host: hostname, port: port),
            authentication: .init(username: username, database: database, password: password),
            tls: .disable
        )
        return try await PostgresConnection.connect(
            on: GlobalEventLoop.sharedGroup.next(),
            configuration: config,
            id: 1,
            logger: Logger(label: "com.swiftlotus.db.postgres")
        ).get()
    }
}
