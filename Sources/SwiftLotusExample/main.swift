import SwiftLotus
import NIOSSL
import Foundation

@main
struct App {
    static func main() async throws {
        // --- 1. Basic Server ---
        let worker = SwiftLotus<TextProtocol>(name: "ChatWorker", uri: "tcp://0.0.0.0:2346")
        
        worker.onConnect = { connection in
            print("[Server] New connection from \(connection.remoteAddress?.description ?? "unknown")")
        }
        
        worker.onMessage = { connection, data in
            print("[Server] Received: \(data)")
            try? await connection.send("Hello " + data)
        }
        
        // --- 2. Timer Example ---
        SwiftLotusTimer.add(timeInterval: 5.0) {
            print("[Timer] Tick (5s)")
        }
        
        // --- 3. AsyncTcpConnection (Client) Example ---
        // Connect to itself after a delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s delay
            
            let client = AsyncTcpConnection<TextProtocol>(uri: "tcp://127.0.0.1:2346")
            
            client.onConnect = { conn in
                print("[Client] Connected to server")
                try? await conn.send("I am Client")
            }
            
            client.onMessage = { conn, msg in
                print("[Client] Received from server: \(msg)")
                // Close after receiving
                try? await conn.close()
            }
            
            client.connect()
        }
        
        // Run Server
        try await worker.run()
    }
}
