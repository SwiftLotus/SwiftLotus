import XCTest
@testable import SwiftLotus

final class DistributedRoutingTests: XCTestCase {
    func testRouteTableTracksGatewayNodesAndUidGroups() {
        let table = GatewayRouteTable()
        let node = GatewayNode(id: "gateway-a", address: "127.0.0.1:9001")

        table.register(node)
        table.bind(connectionId: "c1", uid: "alice", nodeId: node.id)
        table.join(connectionId: "c1", group: "room-1", nodeId: node.id)

        XCTAssertEqual(table.node(id: node.id), node)
        XCTAssertEqual(table.routes(forUid: "alice"), [GatewayRoute(connectionId: "c1", nodeId: node.id)])
        XCTAssertEqual(table.routes(inGroup: "room-1"), [GatewayRoute(connectionId: "c1", nodeId: node.id)])

        table.unregister(nodeId: node.id)

        XCTAssertNil(table.node(id: node.id))
        XCTAssertTrue(table.routes(forUid: "alice").isEmpty)
        XCTAssertTrue(table.routes(inGroup: "room-1").isEmpty)
    }

    func testGatewayControlMessageRoundTripsThroughJSON() throws {
        let message = GatewayControlMessage.bindUid(connectionId: "c1", uid: "alice", nodeId: "gateway-a")
        let encoded = try message.encodedLine()
        let decoded = try GatewayControlMessage.decodeLine(encoded)

        XCTAssertEqual(decoded, message)
    }
}
