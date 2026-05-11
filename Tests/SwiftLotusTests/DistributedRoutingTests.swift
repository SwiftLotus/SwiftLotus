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

    func testGatewayDeliveryPlaneRoutesUidGroupAndBroadcastAcrossNodes() async {
        let table = GatewayRouteTable()
        let nodeA = GatewayNode(id: "gateway-a", address: "127.0.0.1:9001")
        let nodeB = GatewayNode(id: "gateway-b", address: "127.0.0.1:9002")
        table.register(nodeA)
        table.register(nodeB)
        table.bind(connectionId: "c1", uid: "alice", nodeId: nodeA.id)
        table.bind(connectionId: "c3", uid: "alice", nodeId: nodeA.id)
        table.bind(connectionId: "c2", uid: "bob", nodeId: nodeB.id)
        table.join(connectionId: "c2", group: "room-1", nodeId: nodeB.id)
        table.join(connectionId: "c4", group: "room-1", nodeId: nodeB.id)

        let recorder = GatewayDeliveryRecorder()
        let plane = GatewayDeliveryPlane(routes: table) { node, envelope in
            await recorder.append("\(node.id):\(envelope.payload)")
        }

        let uidReport = await plane.deliver(.init(target: .uid("alice"), payload: "hello"))
        let groupReport = await plane.deliver(.init(target: .group("room-1"), payload: "group"))
        let broadcastReport = await plane.deliver(.init(target: .broadcast, payload: "all"))

        XCTAssertEqual(uidReport.deliveredCount, 1)
        XCTAssertEqual(uidReport.attemptedCount, 1)
        XCTAssertEqual(groupReport.deliveredCount, 1)
        XCTAssertEqual(groupReport.attemptedCount, 1)
        XCTAssertEqual(broadcastReport.deliveredCount, 2)
        XCTAssertEqual(broadcastReport.attemptedCount, 2)
        let values = await recorder.values.sorted()
        XCTAssertEqual(values, [
            "gateway-a:all",
            "gateway-a:hello",
            "gateway-b:all",
            "gateway-b:group",
        ])
    }
}

private actor GatewayDeliveryRecorder {
    private var stored: [String] = []

    func append(_ value: String) {
        stored.append(value)
    }

    var values: [String] {
        stored
    }
}
