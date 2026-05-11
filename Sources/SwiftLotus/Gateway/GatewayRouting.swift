import Foundation
import NIOConcurrencyHelpers

public struct GatewayNode: Codable, Equatable, Sendable {
    public let id: String
    public let address: String

    public init(id: String, address: String) {
        self.id = id
        self.address = address
    }
}

public struct GatewayRoute: Codable, Equatable, Hashable, Sendable {
    public let connectionId: String
    public let nodeId: String

    public init(connectionId: String, nodeId: String) {
        self.connectionId = connectionId
        self.nodeId = nodeId
    }
}

public enum GatewayControlMessage: Codable, Equatable, Sendable {
    case registerNode(GatewayNode)
    case unregisterNode(nodeId: String)
    case bindUid(connectionId: String, uid: String, nodeId: String)
    case unbindUid(connectionId: String, uid: String)
    case joinGroup(connectionId: String, group: String, nodeId: String)
    case leaveGroup(connectionId: String, group: String)
    case heartbeat(nodeId: String)

    public func encodedLine() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    public static func decodeLine(_ line: String) throws -> GatewayControlMessage {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(GatewayControlMessage.self, from: Data(trimmed.utf8))
    }
}

public final class GatewayRouteTable: @unchecked Sendable {
    private let lock = NIOLock()
    private var nodesById: [String: GatewayNode] = [:]
    private var routesByUid: [String: Set<GatewayRoute>] = [:]
    private var routesByGroup: [String: Set<GatewayRoute>] = [:]
    private var routesByNode: [String: Set<GatewayRoute>] = [:]
    private var routesByConnectionId: [String: Set<GatewayRoute>] = [:]

    public init() {}

    public func register(_ node: GatewayNode) {
        lock.withLock {
            nodesById[node.id] = node
        }
    }

    public func unregister(nodeId: String) {
        lock.withLock {
            nodesById.removeValue(forKey: nodeId)
            routesByNode.removeValue(forKey: nodeId)
            for connectionId in Array(routesByConnectionId.keys) {
                routesByConnectionId[connectionId] = routesByConnectionId[connectionId]?.filter { $0.nodeId != nodeId }
                if routesByConnectionId[connectionId]?.isEmpty == true {
                    routesByConnectionId.removeValue(forKey: connectionId)
                }
            }

            for uid in Array(routesByUid.keys) {
                routesByUid[uid] = routesByUid[uid]?.filter { $0.nodeId != nodeId }
                if routesByUid[uid]?.isEmpty == true {
                    routesByUid.removeValue(forKey: uid)
                }
            }

            for group in Array(routesByGroup.keys) {
                routesByGroup[group] = routesByGroup[group]?.filter { $0.nodeId != nodeId }
                if routesByGroup[group]?.isEmpty == true {
                    routesByGroup.removeValue(forKey: group)
                }
            }
        }
    }

    public func node(id: String) -> GatewayNode? {
        lock.withLock { nodesById[id] }
    }

    public var nodes: [GatewayNode] {
        lock.withLock {
            nodesById.values.sorted { $0.id < $1.id }
        }
    }

    public func bind(connectionId: String, uid: String, nodeId: String) {
        let route = GatewayRoute(connectionId: connectionId, nodeId: nodeId)
        lock.withLock {
            routesByUid[uid, default: []].insert(route)
            routesByNode[nodeId, default: []].insert(route)
            routesByConnectionId[connectionId, default: []].insert(route)
        }
    }

    public func unbind(connectionId: String, uid: String) {
        lock.withLock {
            guard let routes = routesByUid[uid] else { return }
            for route in routes where route.connectionId == connectionId {
                routesByUid[uid]?.remove(route)
                removeConnectionRouteIfUnreferenced(route)
            }
            if routesByUid[uid]?.isEmpty == true {
                routesByUid.removeValue(forKey: uid)
            }
        }
    }

    public func join(connectionId: String, group: String, nodeId: String) {
        let route = GatewayRoute(connectionId: connectionId, nodeId: nodeId)
        lock.withLock {
            routesByGroup[group, default: []].insert(route)
            routesByNode[nodeId, default: []].insert(route)
            routesByConnectionId[connectionId, default: []].insert(route)
        }
    }

    public func leave(connectionId: String, group: String) {
        lock.withLock {
            guard let routes = routesByGroup[group] else { return }
            for route in routes where route.connectionId == connectionId {
                routesByGroup[group]?.remove(route)
                removeConnectionRouteIfUnreferenced(route)
            }
            if routesByGroup[group]?.isEmpty == true {
                routesByGroup.removeValue(forKey: group)
            }
        }
    }

    public func routes(forUid uid: String) -> [GatewayRoute] {
        lock.withLock {
            (routesByUid[uid] ?? []).sorted { $0.connectionId < $1.connectionId }
        }
    }

    public func routes(inGroup group: String) -> [GatewayRoute] {
        lock.withLock {
            (routesByGroup[group] ?? []).sorted { $0.connectionId < $1.connectionId }
        }
    }

    public func routes(forConnection connectionId: String) -> [GatewayRoute] {
        lock.withLock {
            (routesByConnectionId[connectionId] ?? []).sorted { $0.nodeId < $1.nodeId }
        }
    }

    public func apply(_ message: GatewayControlMessage) {
        switch message {
        case .registerNode(let node):
            register(node)
        case .unregisterNode(let nodeId):
            unregister(nodeId: nodeId)
        case .bindUid(let connectionId, let uid, let nodeId):
            bind(connectionId: connectionId, uid: uid, nodeId: nodeId)
        case .unbindUid(let connectionId, let uid):
            unbind(connectionId: connectionId, uid: uid)
        case .joinGroup(let connectionId, let group, let nodeId):
            join(connectionId: connectionId, group: group, nodeId: nodeId)
        case .leaveGroup(let connectionId, let group):
            leave(connectionId: connectionId, group: group)
        case .heartbeat:
            break
        }
    }

    private func removeConnectionRouteIfUnreferenced(_ route: GatewayRoute) {
        let stillReferencedByUid = routesByUid.values.contains { $0.contains(route) }
        let stillReferencedByGroup = routesByGroup.values.contains { $0.contains(route) }
        guard !stillReferencedByUid && !stillReferencedByGroup else { return }
        routesByConnectionId[route.connectionId]?.remove(route)
        if routesByConnectionId[route.connectionId]?.isEmpty == true {
            routesByConnectionId.removeValue(forKey: route.connectionId)
        }
        routesByNode[route.nodeId]?.remove(route)
        if routesByNode[route.nodeId]?.isEmpty == true {
            routesByNode.removeValue(forKey: route.nodeId)
        }
    }
}
