import Foundation
import NIOCore

public enum SwiftLotusSchedule: Sendable, Equatable {
    case once(after: TimeInterval)
    case every(seconds: TimeInterval)
    case daily(hour: Int, minute: Int, second: Int, calendar: Calendar = Calendar(identifier: .gregorian))

    public func nextRun(after date: Date = Date()) -> Date? {
        switch self {
        case .once(let seconds), .every(let seconds):
            return date.addingTimeInterval(seconds)
        case .daily(let hour, let minute, let second, let calendar):
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = second

            guard let today = calendar.date(from: components) else {
                return nil
            }
            if today > date {
                return today
            }
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
    }

    var isRepeating: Bool {
        switch self {
        case .once:
            return false
        case .every, .daily:
            return true
        }
    }
}

public enum SwiftLotusScheduler {
    @discardableResult
    public static func add(
        _ schedule: SwiftLotusSchedule,
        callback: @escaping @Sendable () async -> Void
    ) -> SwiftLotusTimer.Handle {
        let handle = SwiftLotusTimer.Handle()
        scheduleNext(schedule, handle: handle, callback: callback)
        return handle
    }

    private static func scheduleNext(
        _ schedule: SwiftLotusSchedule,
        handle: SwiftLotusTimer.Handle,
        callback: @escaping @Sendable () async -> Void
    ) {
        let loop = GlobalEventLoop.sharedGroup.next()
        let now = Date()
        let next = schedule.nextRun(after: now) ?? now
        let delay = max(0, next.timeIntervalSince(now))
        let timeAmount = TimeAmount.nanoseconds(Int64(delay * 1_000_000_000))

        let scheduled = loop.scheduleTask(in: timeAmount) {
            if handle.isCancelled { return }
            Task {
                await callback()
                if schedule.isRepeating && !handle.isCancelled {
                    scheduleNext(schedule, handle: handle, callback: callback)
                }
            }
        }
        handle.setScheduled(scheduled)
    }
}
