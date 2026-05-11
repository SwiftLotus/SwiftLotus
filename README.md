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

**SwiftLotus** is an open-source asynchronous TCP networking framework for Swift. Its role is closer to Workerman than to a traditional HTTP MVC framework: it runs as a long-lived event-driven process, manages persistent connections, and lets you build TCP services, custom protocols, WebSocket gateways, proxies, game gateways, IoT gateways, and HTTP endpoints on top of the same core.

Built directly on top of Apple's **SwiftNIO** and Swift 6 **Structured Concurrency (`async/await`)**, it keeps the API approachable while still exposing event-loop oriented fast paths for latency-sensitive handlers.

## 🚀 Why SwiftLotus?

SwiftLotus provides a small, protocol-oriented TCP layer over SwiftNIO:
- **Low Overhead**: Protocol framing is pluggable, so applications can keep parsing and encoding close to the wire format they actually need.
- **Long-Lived Connections by Design**: Managing persistent TCP connections is built-in. Broadcasts and connection tracking can work directly with `worker.connections`.
- **Async by Default, Fast Path When Needed**: Use async callbacks for normal application logic, or `onMessageSync` for tiny non-blocking handlers that should stay on the channel event loop.
- **HTTP as a Built-In Protocol, Not the Core**: HTTP and WebSocket are included, but the framework is designed around TCP connection lifecycle and protocol framing.
- **On-Demand Ecosystem**: Bring your own database. Redis, MySQL, and Postgres adapters live in separate add-on packages, so the root package stays core-only.

## 📦 Features
- **Performance-Oriented Core**: Built on SwiftNIO with explicit event-loop fast paths for hot handlers.
- **Concurrency Safe**: Fully audited with `NIOLock` and `@Sendable` to guarantee thread-safety in Swift 6.
- **OOM Protection**: Built-in generic payload size limiters (Memory Shields).
- **Built-in Protocols**: TCP, HTTP/1.1, WebSocket, Text (Newline), and Frame (Length-prefixed binary).
- **Modular DB Access**: Optional add-on packages for `RediStack`, `MySQLNIO`, and `PostgresNIO`.
- **EventLoop Timers**: Native NIO-backed timers for recurring jobs.

## ⚡️ Performance Benchmarks
The local benchmark suites under `Benchmarks/TCP` and `Benchmarks/HTTP` compare minimal SwiftLotus servers with minimal raw SwiftNIO servers on the same machine. These are regression benchmarks for framework overhead, not industry rankings.

Latest TCP line echo run:

```text
Tool:                   TCPBenchmarkClient
Command:                --connections 100 --requests 200000
Connections:            100
Complete requests:      200000
Failed requests:        0

SwiftLotus TCP:         80048.22 messages/sec
Raw SwiftNIO TCP:       82205.91 messages/sec
```

The HTTP benchmark is still available under `Benchmarks/HTTP` for HTTP-specific overhead checks. For formal cross-framework HTTP comparisons, use TechEmpower Framework Benchmarks. TFB uses stricter response requirements, HTTP pipelining, `wrk`, high concurrency levels, and controlled hardware. SwiftLotus' local benchmarks are intentionally smaller and easier to run during development.

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
Use the Redis add-on when your application needs shared Redis access alongside SwiftLotus networking.

```swift
import SwiftLotus
import SwiftLotusRedis
import RediStack

@main
struct App {
    static func main() async throws {
        // Set up the shared Redis pool.
        try SwiftLotusRedis.setup(hostname: "127.0.0.1", port: 6379)
        
        let worker = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")
        
        worker.onMessage = { connection, request in
            let count = try await SwiftLotusRedis.pool.increment(RedisKey("views")).get()
            
            try await connection.send(HttpResponse(body: "Views: \(count)"))
        }
        
        try await worker.run()
    }
}
```

### 4. Precision EventLoop Timers
```swift
// Executes on an EventLoop-backed timer.
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
