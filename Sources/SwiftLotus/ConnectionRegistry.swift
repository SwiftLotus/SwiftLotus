import Foundation
import NIOConcurrencyHelpers

/// Tracks live connections by id, user id, and group for long-lived TCP style services.
public final class ConnectionRegistry<P: ProtocolInterface>: @unchecked Sendable {
    private let lock = NIOLock()
    private var connectionsById: [UUID: Connection<P>] = [:]
    private var uidByConnectionId: [UUID: String] = [:]
    private var connectionIdsByUid: [String: Set<UUID>] = [:]
    private var groupIdsByConnectionId: [UUID: Set<String>] = [:]
    private var connectionIdsByGroup: [String: Set<UUID>] = [:]

    public init() {}

    public var connectionCount: Int {
        lock.withLock { connectionsById.count }
    }

    public var allConnections: [UUID: Connection<P>] {
        lock.withLock { connectionsById }
    }

    public func add(_ connection: Connection<P>) {
        lock.withLock {
            connectionsById[connection.id] = connection
        }
    }

    public func remove(_ connection: Connection<P>) {
        lock.withLock {
            connectionsById.removeValue(forKey: connection.id)

            if let uid = uidByConnectionId.removeValue(forKey: connection.id) {
                connectionIdsByUid[uid]?.remove(connection.id)
                if connectionIdsByUid[uid]?.isEmpty == true {
                    connectionIdsByUid.removeValue(forKey: uid)
                }
            }

            let groups = groupIdsByConnectionId.removeValue(forKey: connection.id) ?? []
            for group in groups {
                connectionIdsByGroup[group]?.remove(connection.id)
                if connectionIdsByGroup[group]?.isEmpty == true {
                    connectionIdsByGroup.removeValue(forKey: group)
                }
            }
        }
    }

    public func bind(_ connection: Connection<P>, uid: String) {
        lock.withLock {
            if let oldUid = uidByConnectionId[connection.id], oldUid != uid {
                connectionIdsByUid[oldUid]?.remove(connection.id)
                if connectionIdsByUid[oldUid]?.isEmpty == true {
                    connectionIdsByUid.removeValue(forKey: oldUid)
                }
            }

            connectionsById[connection.id] = connection
            uidByConnectionId[connection.id] = uid
            connectionIdsByUid[uid, default: []].insert(connection.id)
        }
    }

    public func unbind(_ connection: Connection<P>) {
        lock.withLock {
            guard let uid = uidByConnectionId.removeValue(forKey: connection.id) else {
                return
            }
            connectionIdsByUid[uid]?.remove(connection.id)
            if connectionIdsByUid[uid]?.isEmpty == true {
                connectionIdsByUid.removeValue(forKey: uid)
            }
        }
    }

    public func join(_ connection: Connection<P>, group: String) {
        lock.withLock {
            connectionsById[connection.id] = connection
            groupIdsByConnectionId[connection.id, default: []].insert(group)
            connectionIdsByGroup[group, default: []].insert(connection.id)
        }
    }

    public func leave(_ connection: Connection<P>, group: String) {
        lock.withLock {
            groupIdsByConnectionId[connection.id]?.remove(group)
            if groupIdsByConnectionId[connection.id]?.isEmpty == true {
                groupIdsByConnectionId.removeValue(forKey: connection.id)
            }

            connectionIdsByGroup[group]?.remove(connection.id)
            if connectionIdsByGroup[group]?.isEmpty == true {
                connectionIdsByGroup.removeValue(forKey: group)
            }
        }
    }

    public func connections(forUid uid: String) -> [Connection<P>] {
        lock.withLock {
            let ids = connectionIdsByUid[uid] ?? []
            return ids.compactMap { connectionsById[$0] }
        }
    }

    public func connections(inGroup group: String) -> [Connection<P>] {
        lock.withLock {
            let ids = connectionIdsByGroup[group] ?? []
            return ids.compactMap { connectionsById[$0] }
        }
    }

    public func send(toUid uid: String, _ data: P.Response) async throws -> Int {
        try await send(to: connections(forUid: uid), data)
    }

    public func send(toGroup group: String, _ data: P.Response) async throws -> Int {
        try await send(to: connections(inGroup: group), data)
    }

    public func broadcast(_ data: P.Response) async throws -> Int {
        try await send(to: Array(allConnections.values), data)
    }

    private func send(to connections: [Connection<P>], _ data: P.Response) async throws -> Int {
        var delivered = 0
        for connection in connections {
            try await connection.send(data)
            delivered += 1
        }
        return delivered
    }
}
