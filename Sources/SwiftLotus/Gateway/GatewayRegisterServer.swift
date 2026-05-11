import Foundation
import NIOCore

public final class GatewayRegisterServer: @unchecked Sendable {
    public let worker: SwiftLotus<TextProtocol>
    public let routes: GatewayRouteTable

    public init(name: String = "GatewayRegister", uri: String, routes: GatewayRouteTable = GatewayRouteTable()) {
        self.worker = SwiftLotus<TextProtocol>(name: name, uri: uri)
        self.routes = routes

        self.worker.onMessage = { [routes] connection, line in
            do {
                let message = try GatewayControlMessage.decodeLine(line)
                routes.apply(message)
                try? await connection.send("OK")
            } catch {
                try? await connection.send("ERR \(error)")
            }
        }
    }

    public func run() async throws {
        try await worker.run()
    }
}

public final class GatewayRegisterClient: @unchecked Sendable {
    private let connection: AsyncTcpConnection<TextProtocol>

    public init(uri: String, reconnectPolicy: ReconnectPolicy = .fixedDelay(maxAttempts: nil, delay: .seconds(1))) {
        self.connection = AsyncTcpConnection<TextProtocol>(uri: uri, reconnectPolicy: reconnectPolicy)
    }

    public var onError: (@Sendable (Error) async -> Void)? {
        get { connection.onError }
        set { connection.onError = newValue }
    }

    public func connect() {
        connection.connect()
    }

    public func send(_ message: GatewayControlMessage) async throws {
        guard let active = connection.connection else {
            throw SwiftLotusError.invalidURI("GatewayRegisterClient is not connected")
        }
        try await active.send(message.encodedLine().trimmingCharacters(in: .newlines))
    }
}
