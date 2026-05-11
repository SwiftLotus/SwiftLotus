import Foundation
import NIOConcurrencyHelpers

public struct SwiftLotusEventSubscription: Sendable, Hashable {
    public let id: UUID
    public let topic: String
}

public final class SwiftLotusEventBus<Message: Sendable>: @unchecked Sendable {
    public typealias Handler = @Sendable (Message) async -> Void

    private let lock = NIOLock()
    private var handlersByTopic: [String: [UUID: Handler]] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ topic: String, handler: @escaping Handler) -> SwiftLotusEventSubscription {
        let id = UUID()
        lock.withLock {
            handlersByTopic[topic, default: [:]][id] = handler
        }
        return SwiftLotusEventSubscription(id: id, topic: topic)
    }

    public func unsubscribe(_ subscription: SwiftLotusEventSubscription) {
        lock.withLock {
            handlersByTopic[subscription.topic]?.removeValue(forKey: subscription.id)
            if handlersByTopic[subscription.topic]?.isEmpty == true {
                handlersByTopic.removeValue(forKey: subscription.topic)
            }
        }
    }

    public func publish(_ topic: String, _ message: Message) async {
        let handlers: [Handler] = lock.withLock {
            guard let values = handlersByTopic[topic]?.values else {
                return []
            }
            return Array(values)
        }

        for handler in handlers {
            await handler(message)
        }
    }
}
