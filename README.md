<p align="center">
  <img src="icon.png" width="200" alt="SwiftLotus Logo">
</p>

# SwiftLotus 🪷

<p align="center">
    <b>English</b> | <a href="README_zh.md">中文版</a>
</p>

<p align="center">
    <a href="http://opensource.org/licenses/MIT">
        <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat" alt="MIT License">
    </a>
    <a href="https://swift.org">
        <img src="https://design.vapor.codes/images/swift60up.svg" alt="Swift 6.0+">
    </a>
</p>

**SwiftLotus** is an open-source, ultra high-performance, asynchronous non-blocking underlying Socket engine for Swift. It is not just an HTTP web framework, but a highly generic and foundational network service engine. You can use it to easily develop massive-concurrency TCP proxies, distributed multiplayer game server backends, custom IoT communication gateways, and any network service cluster requiring extreme throughput and real-time bidirectional interaction.

Built directly on top of Apple's **SwiftNIO** and leveraging Swift 6 **Structured Concurrency (`async/await`)**, it provides bare-metal Socket throughput while maintaining a beautifully simple API.

## 🚀 Why SwiftLotus?

SwiftLotus provides a lightweight, elegant, and bare-metal approach to backend network development:
- **Zero Overhead**: Exposes raw TCP/UDP streams natively. Pluggable protocols with absolute minimum runtime padding.
- **Stateful by Design**: Managing persistent connections is built-in. Want to broadcast a message to 10,000 connected players? Just loop over `worker.connections`.
- **True Shared-Threading**: Shares a single ultra-fast `GlobalEventLoop` (epoll/kqueue) across your entire app infrastructure, drastically eliminating threading context switch taxes.
- **On-Demand Ecosystem**: Bring your own database. We provide modular wrappers for Redis, MySQL, and Postgres without forcing you to download them if you don't need them.

## 📦 Features
- **Uncompromising Performance**: Built on SwiftNIO (Zero Context Switch design).
- **Concurrency Safe**: Fully audited with `NIOLock` and `@Sendable` to guarantee thread-safety in Swift 6.
- **OOM Protection**: Built-in generic payload size limiters (Memory Shields).
- **Built-in Protocols**: TCP, HTTP/1.1, WebSocket, Text (Newline), and Frame (Length-prefixed binary).
- **Modular DB Access**: Direct integration targets for `RediStack`, `MySQLNIO`, and `PostgresNIO`.
- **High-Precision Timers**: Native NIO-backed event-loop timers (bypassing unstructured `Task.sleep` overhead).

## ⚡️ Performance Benchmark
Running a generic HTTP Ping-Pong using `SwiftLotus<HttpProtocol>` **without Keep-Alive** (forcing full raw TCP handshakes per individual request) on a standard development machine yields massive throughput at **> 10,000+ RPS**, with sub-millisecond response guarantees. With persistent connections (`wrk -c`), throughput scales exponentially to physical NIC limits.

```text
Concurrency Level:      100
Complete requests:      20000
Failed requests:        0
Requests per second:    10496.17 [#/sec] (mean)
Time per request:       0.095 [ms] (mean, across all concurrent requests)
```
*Tested via Apache Bench (`ab -c 100 -n 20000`)*

## 🛠 Environment Setup

- Swift 6.0+
- macOS 14+ or Linux (Ubuntu 20.04+, Amazon Linux 2, etc.)

## 📦 Installation

Add SwiftLotus to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),
]
```

### On-Demand Modules (Target Splitting)
To keep your dependency tree clean, databases are strictly opt-in. Select only what you use:
```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftLotus", package: "SwiftLotus"),          // The core engine
            .product(name: "SwiftLotusRedis", package: "SwiftLotus"),     // Opt-in Redis
            .product(name: "SwiftLotusMySQL", package: "SwiftLotus"),     // Opt-in MySQL
            // .product(name: "SwiftLotusPostgres", package: "SwiftLotus") // Opt-in Postgres
        ]
    )
]
```

## ⏱ Quick Start

### 1. TCP Chat Server with Broadcast
Easily build an IM backend using the built-in Connection Pool.

```swift
import SwiftLotus

@main
struct App {
    static func main() async throws {
        // Listen on port 2346 using Text (newline-separated) protocol
        let worker = SwiftLotus<TextProtocol>(name: "ChatServer", uri: "tcp://0.0.0.0:2346")
        
        worker.onConnect = { connection in
            print("User connected: \(connection.id)")
        }
        
        worker.onMessage = { connection, message in
            // Broadcast to all connected users instantly
            worker.connections.values.forEach { sibling in 
                try? await sibling.send("User \(connection.id) says: \(message)")
            }
        }
        
        try await worker.run()
    }
}
```

### 2. High-Performance WebSocket Server
Zero-config WebSocket upgrades with OOM safety out-of-the-box.

```swift
import SwiftLotus

let worker = SwiftLotus<WebSocketProtocol>(name: "WSServer", uri: "websocket://0.0.0.0:8080")

worker.onMessage = { connection, frame in
    // Automatically decodes binary/text WebSocket frames
    try? await connection.send("Echo: " + frame.string)
}

try await worker.run()
```

### 3. Native Database Connectivity (Redis Example)
Integrate external DB calls seamlessly onto the exact same C-level network threads (Zero Context Switching).

```swift
import SwiftLotus
import SwiftLotusRedis

@main
struct App {
    static func main() async throws {
        // Setup Redis Pool on the shared EventLoop
        try SwiftLotusRedis.setup(hostname: "127.0.0.1", port: 6379)
        
        let worker = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")
        
        worker.onMessage = { connection, request in
            // Async DB fetch without blocking any threads!
            let count = try await SwiftLotusRedis.pool.increment(RedisKey("views")).get()
            
            try await connection.send(HttpResponse(body: "Views: \(count)"))
        }
        
        try await worker.run()
    }
}
```

### 4. Precision EventLoop Timers
```swift
// Executes directly on the global EventLoop (Extreme precision, zero Task.sleep spawning overhead)
let timer = SwiftLotusTimer.add(timeInterval: 1.0) {
    print("Running every second...")
}

// SwiftLotusTimer.del(timer)
```

## 🏗 Architecture
*   **SwiftLotus**: The main worker class managing the event loop, socket binding, and automatic connection pooling.
*   **ProtocolInterface**: Defines how raw `ByteBuffer`s are framed, encoded, and decoded. Unopinionated.
*   **Connection**: Represents a client connection, generic over the protocol. Thread-safe.

## 📄 License

MIT
