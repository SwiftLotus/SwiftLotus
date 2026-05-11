import Foundation

public enum GatewayDeliveryTarget: Codable, Equatable, Sendable {
    case connection(String)
    case uid(String)
    case group(String)
    case broadcast
}

public struct GatewayDeliveryEnvelope: Codable, Equatable, Sendable {
    public let id: String
    public let target: GatewayDeliveryTarget
    public let payload: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        target: GatewayDeliveryTarget,
        payload: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.target = target
        self.payload = payload
        self.createdAt = createdAt
    }
}

public struct GatewayDeliveryFailure: Equatable, Sendable {
    public let node: GatewayNode
    public let route: GatewayRoute?
    public let errorDescription: String
}

public struct GatewayDeliveryReport: Equatable, Sendable {
    public let envelope: GatewayDeliveryEnvelope
    public let attemptedCount: Int
    public let deliveredCount: Int
    public let failures: [GatewayDeliveryFailure]
}

public final class GatewayDeliveryPlane: @unchecked Sendable {
    public typealias DeliveryHandler = @Sendable (GatewayNode, GatewayDeliveryEnvelope) async throws -> Void

    private let routes: GatewayRouteTable
    private let deliverToNode: DeliveryHandler

    public init(routes: GatewayRouteTable, deliverToNode: @escaping DeliveryHandler) {
        self.routes = routes
        self.deliverToNode = deliverToNode
    }

    public func deliver(_ envelope: GatewayDeliveryEnvelope) async -> GatewayDeliveryReport {
        let destinations = destinations(for: envelope.target)
        var delivered = 0
        var failures: [GatewayDeliveryFailure] = []

        for destination in destinations {
            do {
                try await deliverToNode(destination.node, envelope)
                delivered += 1
            } catch {
                failures.append(
                    GatewayDeliveryFailure(
                        node: destination.node,
                        route: destination.route,
                        errorDescription: String(describing: error)
                    )
                )
            }
        }

        return GatewayDeliveryReport(
            envelope: envelope,
            attemptedCount: destinations.count,
            deliveredCount: delivered,
            failures: failures
        )
    }

    private func destinations(for target: GatewayDeliveryTarget) -> [GatewayDeliveryDestination] {
        switch target {
        case .connection(let connectionId):
            return routes.routes(forConnection: connectionId).compactMap(destination(for:))
        case .uid(let uid):
            return uniqueNodeDestinations(for: routes.routes(forUid: uid))
        case .group(let group):
            return uniqueNodeDestinations(for: routes.routes(inGroup: group))
        case .broadcast:
            return routes.nodes.map {
                GatewayDeliveryDestination(node: $0, route: nil)
            }
        }
    }

    private func uniqueNodeDestinations(for targetRoutes: [GatewayRoute]) -> [GatewayDeliveryDestination] {
        var seenNodeIds = Set<String>()
        var destinations: [GatewayDeliveryDestination] = []

        for route in targetRoutes {
            guard let destination = destination(for: route) else {
                continue
            }
            guard seenNodeIds.insert(destination.node.id).inserted else {
                continue
            }
            destinations.append(destination)
        }

        return destinations
    }

    private func destination(for route: GatewayRoute) -> GatewayDeliveryDestination? {
        guard let node = routes.node(id: route.nodeId) else {
            return nil
        }
        return GatewayDeliveryDestination(node: node, route: route)
    }
}

private struct GatewayDeliveryDestination {
    let node: GatewayNode
    let route: GatewayRoute?
}
