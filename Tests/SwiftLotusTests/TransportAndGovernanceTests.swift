import XCTest
import NIOCore
@testable import SwiftLotus

final class TransportAndGovernanceTests: XCTestCase {
    func testConnectionGovernorRejectsGlobalAndPerIPLimits() {
        var governor = ConnectionGovernor(limits: ConnectionLimits(maxConnections: 2, maxConnectionsPerIP: 1))

        XCTAssertEqual(governor.evaluateConnection(remoteIP: "10.0.0.1"), .accepted)
        governor.recordAcceptedConnection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, remoteIP: "10.0.0.1")

        XCTAssertEqual(governor.evaluateConnection(remoteIP: "10.0.0.1"), .rejected(.maxConnectionsPerIP))
        XCTAssertEqual(governor.evaluateConnection(remoteIP: "10.0.0.2"), .accepted)
        governor.recordAcceptedConnection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, remoteIP: "10.0.0.2")

        XCTAssertEqual(governor.evaluateConnection(remoteIP: "10.0.0.3"), .rejected(.maxConnections))
    }

    func testUnixSocketURIIsParsedAsEndpoint() {
        let worker = SwiftLotus<TextProtocol>(name: "UnixTest", uri: "unix:///tmp/swiftlotus-test.sock", enableSignalHandlers: false)

        XCTAssertEqual(worker.endpoint, .unix(path: "/tmp/swiftlotus-test.sock"))
    }

    func testUDPServerParsesURIAndExposesStatus() {
        let server = SwiftLotusUDP<TextProtocol>(name: "UDPTest", uri: "udp://127.0.0.1:9000")

        XCTAssertEqual(server.name, "UDPTest")
        XCTAssertEqual(server.host, "127.0.0.1")
        XCTAssertEqual(server.port, 9000)
        XCTAssertFalse(server.status.isRunning)
    }
}
