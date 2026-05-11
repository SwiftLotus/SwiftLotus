import Foundation
import NIOConcurrencyHelpers

public struct SwiftLotusDurationSummary: Sendable, Equatable {
    public let count: Int
    public let totalSeconds: Double
    public let minSeconds: Double
    public let maxSeconds: Double

    public var averageSeconds: Double {
        count == 0 ? 0 : totalSeconds / Double(count)
    }
}

public struct SwiftLotusMetricsSnapshot: Sendable, Equatable {
    public let counters: [String: Int64]
    public let gauges: [String: Double]
    public let durations: [String: SwiftLotusDurationSummary]
}

public final class SwiftLotusMetrics: @unchecked Sendable {
    private let lock = NIOLock()
    private var counters: [String: Int64] = [:]
    private var gauges: [String: Double] = [:]
    private var durations: [String: SwiftLotusDurationAccumulator] = [:]

    public init() {}

    public func incrementCounter(_ name: String, by amount: Int64 = 1) {
        lock.withLock {
            counters[name, default: 0] += amount
        }
    }

    public func setGauge(_ name: String, value: Double) {
        lock.withLock {
            gauges[name] = value
        }
    }

    public func recordDuration(_ name: String, seconds: Double) {
        lock.withLock {
            durations[name, default: SwiftLotusDurationAccumulator()].record(seconds)
        }
    }

    public func snapshot() -> SwiftLotusMetricsSnapshot {
        lock.withLock {
            SwiftLotusMetricsSnapshot(
                counters: counters,
                gauges: gauges,
                durations: durations.mapValues { $0.summary }
            )
        }
    }
}

private struct SwiftLotusDurationAccumulator {
    var count = 0
    var totalSeconds = 0.0
    var minSeconds = Double.greatestFiniteMagnitude
    var maxSeconds = 0.0

    mutating func record(_ seconds: Double) {
        count += 1
        totalSeconds += seconds
        minSeconds = min(minSeconds, seconds)
        maxSeconds = max(maxSeconds, seconds)
    }

    var summary: SwiftLotusDurationSummary {
        SwiftLotusDurationSummary(
            count: count,
            totalSeconds: totalSeconds,
            minSeconds: count == 0 ? 0 : minSeconds,
            maxSeconds: maxSeconds
        )
    }
}
