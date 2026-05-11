import Foundation
import NIOCore

public struct ConnectionLimits: Sendable, Equatable {
    public var maxConnections: Int?
    public var maxConnectionsPerIP: Int?
    public var authenticationTimeout: TimeAmount?

    public static let none = ConnectionLimits()

    public init(maxConnections: Int? = nil, maxConnectionsPerIP: Int? = nil, authenticationTimeout: TimeAmount? = nil) {
        self.maxConnections = maxConnections
        self.maxConnectionsPerIP = maxConnectionsPerIP
        self.authenticationTimeout = authenticationTimeout
    }
}

public enum ConnectionRejectionReason: Sendable, Equatable {
    case maxConnections
    case maxConnectionsPerIP
}

public enum ConnectionDecision: Sendable, Equatable {
    case accepted
    case rejected(ConnectionRejectionReason)
}

public struct ConnectionGovernor: Sendable, Equatable {
    public var limits: ConnectionLimits
    private var connectionIds: Set<UUID> = []
    private var remoteIPByConnectionId: [UUID: String] = [:]
    private var connectionCountByIP: [String: Int] = [:]

    public init(limits: ConnectionLimits = .none) {
        self.limits = limits
    }

    public var connectionCount: Int {
        connectionIds.count
    }

    public func evaluateConnection(remoteIP: String?) -> ConnectionDecision {
        if let maxConnections = limits.maxConnections, connectionCount >= maxConnections {
            return .rejected(.maxConnections)
        }

        if let remoteIP,
           let maxConnectionsPerIP = limits.maxConnectionsPerIP,
           (connectionCountByIP[remoteIP] ?? 0) >= maxConnectionsPerIP {
            return .rejected(.maxConnectionsPerIP)
        }

        return .accepted
    }

    public mutating func recordAcceptedConnection(id: UUID, remoteIP: String?) {
        connectionIds.insert(id)
        guard let remoteIP else { return }
        remoteIPByConnectionId[id] = remoteIP
        connectionCountByIP[remoteIP, default: 0] += 1
    }

    public mutating func recordClosedConnection(id: UUID) {
        connectionIds.remove(id)
        guard let remoteIP = remoteIPByConnectionId.removeValue(forKey: id) else { return }
        connectionCountByIP[remoteIP, default: 0] -= 1
        if (connectionCountByIP[remoteIP] ?? 0) <= 0 {
            connectionCountByIP.removeValue(forKey: remoteIP)
        }
    }
}
