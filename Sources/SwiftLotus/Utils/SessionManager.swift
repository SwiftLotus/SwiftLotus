import Foundation

/// Simple in-memory Session Manager
public actor SessionManager {
    public static let shared = SessionManager()
    
    private var sessions: [String: [String: String]] = [:]
    
    /// Get session data
    public func get(_ sessionId: String) -> [String: String] {
        return sessions[sessionId] ?? [:]
    }
    
    /// Set session data
    public func set(_ sessionId: String, data: [String: String]) {
        sessions[sessionId] = data
    }
    
    /// Update a value
    public func update(_ sessionId: String, key: String, value: String) {
        var data = sessions[sessionId] ?? [:]
        data[key] = value
        sessions[sessionId] = data
    }
    
    /// Create a new Session ID
    public func createSessionId() -> String {
        return UUID().uuidString
    }
}
