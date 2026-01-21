import Foundation

/// A simple timer facility.
/// Uses Swift's native concurrency (Task.sleep).
public struct SwiftLotusTimer {
    
    /// Add a timer.
    /// - Parameters:
    ///   - timeInterval: Interval in seconds.
    ///   - persistent: Whether to repeat the timer.
    ///   - callback: The closure to execute.
    /// - Returns: A Task handle that can be used to cancel the timer.
    @discardableResult
    public static func add(timeInterval: TimeInterval, persistent: Bool = true, callback: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        return Task {
            // Initial delay
            try? await Task.sleep(nanoseconds: UInt64(timeInterval * 1_000_000_000))
            
            if Task.isCancelled { return }
            await callback()
            
            if persistent {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(timeInterval * 1_000_000_000))
                    if Task.isCancelled { return }
                    await callback()
                }
            }
        }
    }
    
    /// Delete a timer (cancel the task).
    public static func del(_ timer: Task<Void, Never>) {
        timer.cancel()
    }
}
