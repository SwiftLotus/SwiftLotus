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
The local benchmark suite under `Benchmarks/HTTP` compares a minimal `SwiftLotus<HttpProtocol>` server with a minimal raw SwiftNIO HTTP server on the same machine. This is a regression benchmark for framework overhead, not an industry ranking.

Latest local run:

```text
Tool:                   ApacheBench
Command:                ab -n 200000 -c 100 -k
Concurrency Level:      100
Complete requests:      200000
Failed requests:        0

SwiftLotus HTTP:        80707.74 requests/sec
Raw SwiftNIO HTTP:      82151.65 requests/sec
```

For formal cross-framework comparisons, use TechEmpower Framework Benchmarks. TFB uses stricter response requirements, HTTP pipelining, `wrk`, high concurrency levels, and controlled hardware. SwiftLotus' local benchmark is intentionally smaller and easier to run during development.

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

### On-Demand Modules
The root package is intentionally core-only: installing `SwiftLotus` does not resolve Redis, MySQL, or Postgres drivers. Database adapters live as separate packages under `Addons/` in this repository, so they can be published independently or used locally during development:

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),

    // Local development in this repository:
    // .package(path: "Addons/SwiftLotusRedis")

    // Published add-on packages can use their own repository URLs:
    // .package(url: "https://github.com/SwiftLotus/SwiftLotusRedis.git", from: "1.0.0"),
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftLotus", package: "SwiftLotus"),
            // .product(name: "SwiftLotusRedis", package: "SwiftLotusRedis"),
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
            for sibling in worker.connections.values {
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

### Event-Loop Fast Path
Use `onMessage` for normal async application logic. For tiny hot-path handlers that only frame and flush a response, `onMessageSync` avoids creating a Swift task per message and runs directly on the channel event loop. Keep this callback non-blocking.

```swift
let worker = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

worker.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
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
