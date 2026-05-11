import XCTest
import NIOCore
import NIOEmbedded
@testable import SwiftLotus

final class ConnectionRegistryTests: XCTestCase {
    func testRegistryBindsUidAndGroupMembershipAndCleansUpOnRemove() {
        let firstChannel = EmbeddedChannel()
        let secondChannel = EmbeddedChannel()
        let first = Connection<TextProtocol>(channel: firstChannel)
        let second = Connection<TextProtocol>(channel: secondChannel)
        let registry = ConnectionRegistry<TextProtocol>()

        registry.add(first)
        registry.add(second)
        registry.bind(first, uid: "alice")
        registry.bind(second, uid: "alice")
        registry.join(first, group: "room-1")

        XCTAssertEqual(Set(registry.connections(forUid: "alice").map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(Set(registry.connections(inGroup: "room-1").map(\.id)), Set([first.id]))

        registry.remove(first)

        XCTAssertEqual(Set(registry.connections(forUid: "alice").map(\.id)), Set([second.id]))
        XCTAssertTrue(registry.connections(inGroup: "room-1").isEmpty)
        XCTAssertEqual(registry.connectionCount, 1)

        XCTAssertNoThrow(try firstChannel.finish(acceptAlreadyClosed: true))
        XCTAssertNoThrow(try secondChannel.finish(acceptAlreadyClosed: true))
    }

    func testWorkerConvenienceMethodsUseRegistry() throws {
        let worker = SwiftLotus<TextProtocol>(name: "RegistryTest", uri: "tcp://127.0.0.1:0", enableSignalHandlers: false)
        let channel = EmbeddedChannel(handler: LotusHandler(worker: worker))

        channel.pipeline.fireChannelActive()

        let connection = try XCTUnwrap(worker.connections.values.first)
        worker.bind(connection, uid: "alice")
        worker.join(connection, group: "room-1")

        XCTAssertEqual(worker.connections(forUid: "alice").first?.id, connection.id)
        XCTAssertEqual(worker.connections(inGroup: "room-1").first?.id, connection.id)

        channel.pipeline.fireChannelInactive()

        XCTAssertTrue(worker.connections(forUid: "alice").isEmpty)
        XCTAssertTrue(worker.connections(inGroup: "room-1").isEmpty)
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }
}
