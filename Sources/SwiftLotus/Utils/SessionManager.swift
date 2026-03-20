import Foundation

/// Internal shard actor to prevent global contention
private actor SessionShard {
    var sessions: [String: [String: String]] = [:]
    
    func get(_ sessionId: String) -> [String: String] {
        return sessions[sessionId] ?? [:]
    }
    
    func set(_ sessionId: String, data: [String: String]) {
        sessions[sessionId] = data
    }
    
    func update(_ sessionId: String, key: String, value: String) {
        var data = sessions[sessionId] ?? [:]
        data[key] = value
        sessions[sessionId] = data
    }
}

/// Simple in-memory Session Manager
public final class SessionManager: @unchecked Sendable {
    public static let shared = SessionManager()
    
    private let shards: [SessionShard]
    private let shardCount = 32
    
    private init() {
        var s = [SessionShard]()
        for _ in 0..<shardCount {
            s.append(SessionShard())
        }
        self.shards = s
    }
    
    private func shard(for sessionId: String) -> SessionShard {
        let hash = abs(sessionId.hashValue)
        return shards[hash % shardCount]
    }
    
    /// Get session data
    public func get(_ sessionId: String) async -> [String: String] {
        return await shard(for: sessionId).get(sessionId)
    }
    
    /// Set session data
    public func set(_ sessionId: String, data: [String: String]) async {
        await shard(for: sessionId).set(sessionId, data: data)
    }
    
    /// Update a value
    public func update(_ sessionId: String, key: String, value: String) async {
        await shard(for: sessionId).update(sessionId, key: key, value: value)
    }
    
    /// Create a new Session ID
    public func createSessionId() -> String {
        return UUID().uuidString
    }
}
