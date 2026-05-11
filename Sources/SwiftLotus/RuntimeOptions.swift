import NIOCore
import Foundation

public enum SwiftLotusIdleEvent: Sendable, Equatable {
    case read
    case write
    case all

    init?(_ event: IdleStateHandler.IdleStateEvent) {
        switch event {
        case .read:
            self = .read
        case .write:
            self = .write
        case .all:
            self = .all
        }
    }
}

public struct ReconnectPolicy: Sendable {
    public let maxAttempts: Int?
    public let delay: TimeAmount

    public static let disabled = ReconnectPolicy(maxAttempts: 0, delay: .seconds(0))

    public static func fixedDelay(maxAttempts: Int? = nil, delay: TimeAmount) -> ReconnectPolicy {
        ReconnectPolicy(maxAttempts: maxAttempts, delay: delay)
    }

    public init(maxAttempts: Int?, delay: TimeAmount) {
        self.maxAttempts = maxAttempts
        self.delay = delay
    }

    public func shouldReconnect(afterFailedAttempt attempt: Int) -> Bool {
        guard maxAttempts != 0 else {
            return false
        }
        guard let maxAttempts else {
            return true
        }
        return attempt < maxAttempts
    }
}

public struct SwiftLotusStatus: Sendable {
    public let name: String
    public let uri: String
    public let threadCount: Int
    public let connectionCount: Int
    public let isRunning: Bool
    public let startedAt: Date?
}
