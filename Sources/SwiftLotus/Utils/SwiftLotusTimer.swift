import Foundation
import NIOCore
import NIOConcurrencyHelpers

/// A simple timer facility.
/// Uses SwiftNIO EventLoop natively for high-performance scheduling.
public struct SwiftLotusTimer {
    
    public final class Handle: @unchecked Sendable {
        private var scheduled: Scheduled<Void>?
        private var cancelled = false
        private let lock = NIOLock()
        
        init() {}
        
        func setScheduled(_ scheduled: Scheduled<Void>) {
            lock.withLock {
                if cancelled {
                    scheduled.cancel()
                } else {
                    self.scheduled = scheduled
                }
            }
        }
        
        public func cancel() {
            lock.withLock {
                cancelled = true
                scheduled?.cancel()
                scheduled = nil
            }
        }
        
        var isCancelled: Bool {
            lock.withLock { return cancelled }
        }
    }
    
    /// Add a timer.
    /// - Parameters:
    ///   - timeInterval: Interval in seconds.
    ///   - persistent: Whether to repeat the timer.
    ///   - callback: The closure to execute.
    /// - Returns: A Handle that can be used to cancel the timer.
    @discardableResult
    public static func add(timeInterval: TimeInterval, persistent: Bool = true, callback: @escaping @Sendable () async -> Void) -> SwiftLotusTimer.Handle {
        let handle = Handle()
        let loop = GlobalEventLoop.sharedGroup.next()
        let delay = TimeAmount.nanoseconds(Int64(timeInterval * 1_000_000_000))
        
        @Sendable func scheduleNext() {
            if handle.isCancelled { return }
            
            let scheduled = loop.scheduleTask(in: delay) {
                if handle.isCancelled { return }
                
                Task {
                    await callback()
                    if persistent && !handle.isCancelled {
                        scheduleNext()
                    }
                }
            }
            handle.setScheduled(scheduled)
        }
        
        scheduleNext()
        return handle
    }
    
    /// Delete a timer (cancel the task).
    public static func del(_ timer: SwiftLotusTimer.Handle) {
        timer.cancel()
    }
}
