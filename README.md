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
- **Long-Lived Connections by Design**: Managing persistent TCP connections is built-in. Broadcasts and connection tracking can work through `worker.connections` or the uid/group registry.
- **Async by Default, Fast Path When Needed**: Use async callbacks for normal application logic, or `onMessageSync` for tiny non-blocking handlers that should stay on the channel event loop.
- **Backpressure and Heartbeats**: Configure write-buffer watermarks, pause/resume reads, and close idle connections with NIO-backed idle events.
- **HTTP as a Built-In Protocol, Not the Core**: HTTP and WebSocket are included, but the framework is designed around TCP connection lifecycle and protocol framing.
- **On-Demand Ecosystem**: Bring your own database. Redis, MySQL, and Postgres adapters live in separate add-on packages, so the root package stays core-only.

## 📦 Features
- **Performance-Oriented Core**: Built on SwiftNIO with explicit event-loop fast paths for hot handlers.
- **Concurrency Safe**: Fully audited with `NIOLock` and `@Sendable` to guarantee thread-safety in Swift 6.
- **OOM Protection**: Built-in generic payload size limiters (Memory Shields).
- **Built-in Protocols**: TCP, HTTP/1.1, WebSocket, Text (Newline), and Frame (Length-prefixed binary).
- **Connection Registry**: Bind connections to user ids, join groups, send to users, send to groups, and broadcast from one worker.
- **Runtime Lifecycle Hooks**: `onWorkerStart`, `onWorkerStop`, `onWorkerReload`, `onError`, `onIdle`, `onBufferFull`, and `onBufferDrain`.
- **Runtime Status Snapshot**: Inspect worker name, URI, thread count, running state, start time, and live connection count.
- **CLI Runtime**: `swiftlotus start|stop|restart|reload|status|connections` can manage compiled SwiftLotus applications with worker environment variables and status files.
- **Gateway Register Primitives**: `GatewayRouteTable`, `GatewayControlMessage`, and register client/server helpers provide the base for GatewayWorker-style distributed routing.
- **UDP and Unix Socket Support**: Run datagram services with `SwiftLotusUDP` and bind stream workers with `unix:///path.sock`.
- **Connection Governance**: Configure max connections, per-IP limits, and authentication timeouts.
- **Async TCP Client Reconnects**: `AsyncTcpConnection` can expose its current connection and use fixed-delay reconnect policies.
- **Ecosystem Components**: Built-in outbound HTTP/HTTPS client, in-process event bus, calendar-aware scheduler, and lightweight metrics collector.
- **Modular DB Access**: Optional add-on packages for `RediStack`, `MySQLNIO`, and `PostgresNIO`.
- **EventLoop Timers**: Native NIO-backed timers for recurring jobs.

### Workerman-Inspired Scope

SwiftLotus now covers most of the Workerman-style building blocks in a SwiftNIO shape: lifecycle callbacks, connection tracking, uid/group routing, idle cleanup, send backpressure, timers and schedules, custom protocols, async outbound TCP clients, an outbound HTTP client, in-process pub/sub, basic metrics, UDP listeners, Unix domain sockets, a CLI process manager, reload signals, and register-table primitives for distributed gateway routing. The runtime manager is intentionally a v1: it starts and signals compiled Swift executables, while advanced supervision policies and a full GatewayWorker-compatible delivery plane can be layered on top.

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

### 1. TCP Chat Server with Groups
Easily build an IM backend using the built-in connection registry.

```swift
import NIOCore
import SwiftLotus

@main
struct App {
    static func main() async throws {
        let worker = SwiftLotus<TextProtocol>(name: "ChatServer", uri: "tcp://0.0.0.0:2346")
        worker.idleTimeout = .seconds(60)
        worker.closeIdleConnections = true
        worker.writeBufferWaterMark = .init(low: 1 * 1024 * 1024, high: 2 * 1024 * 1024)
        
        worker.onConnect = { connection in
            print("User connected: \(connection.id)")
        }

        worker.onBufferFull = { connection in
            connection.pauseRead()
        }

        worker.onBufferDrain = { connection in
            connection.resumeRead()
        }
        
        worker.onMessage = { connection, message in
            if message.hasPrefix("/uid ") {
                worker.bind(connection, uid: String(message.dropFirst(5)))
                return
            }
            worker.join(connection, group: "lobby")
            try? await worker.sendToGroup("lobby", "User \(connection.id) says: \(message)")
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

### 3. Async TCP Client with Reconnects

```swift
import NIOCore
import SwiftLotus

let client = AsyncTcpConnection<TextProtocol>(
    uri: "tcp://127.0.0.1:9000",
    reconnectPolicy: .fixedDelay(maxAttempts: nil, delay: .seconds(1))
)

client.onConnect = { connection in
    try? await connection.send("hello")
}

client.onMessage = { _, message in
    print("upstream:", message)
}

client.connect()
```

### 4. CLI Runtime

Build your application first, then let the CLI manage worker processes:

```bash
swift build -c release
.build/release/swiftlotus start \
  --name chat \
  --command .build/release/YourChatServer \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port

.build/release/swiftlotus status --runtime-dir .swiftlotus
.build/release/swiftlotus reload --runtime-dir .swiftlotus
.build/release/swiftlotus connections --runtime-dir .swiftlotus
.build/release/swiftlotus stop --runtime-dir .swiftlotus
```

Each worker receives `SWIFTLOTUS_WORKER_INDEX`, `SWIFTLOTUS_WORKER_COUNT`, `SWIFTLOTUS_REUSE_PORT`, `SWIFTLOTUS_RUNTIME_DIR`, and `SWIFTLOTUS_RUNTIME_NAME`. `SIGUSR1` triggers `onWorkerReload`; reloadable workers exit after the callback so the manager can start fresh processes.

### 5. UDP and Unix Socket Services

```swift
let udp = SwiftLotusUDP<DatagramTextProtocol>(name: "UDPStats", uri: "udp://0.0.0.0:9000")
udp.onMessage = { address, message, server in
    server.send("ack: \(message)", to: address)
}

let unixWorker = SwiftLotus<TextProtocol>(name: "LocalAgent", uri: "unix:///tmp/swiftlotus-agent.sock")
```

### 6. Register Routing Primitives

```swift
let table = GatewayRouteTable()
table.register(GatewayNode(id: "gateway-a", address: "127.0.0.1:9001"))
table.bind(connectionId: "c1", uid: "alice", nodeId: "gateway-a")
table.join(connectionId: "c1", group: "room-1", nodeId: "gateway-a")

let uidRoutes = table.routes(forUid: "alice")
let groupRoutes = table.routes(inGroup: "room-1")
```

### 7. Native Database Connectivity (Redis Example)
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

### 8. Ecosystem Components
Use the built-in utility components for common long-running service needs without turning the core package into a full application framework.

```swift
let http = SwiftLotusHTTPClient()
let response = try await http.get("http://127.0.0.1:8080/health")
print(response.status, response.body)

let bus = SwiftLotusEventBus<String>()
bus.subscribe("jobs.created") { jobId in
    print("job created:", jobId)
}
await bus.publish("jobs.created", "42")

let metrics = SwiftLotusMetrics()
metrics.incrementCounter("messages")
metrics.setGauge("connections", value: 12)

let timer = SwiftLotusScheduler.add(.every(seconds: 5)) {
    metrics.recordDuration("heartbeat", seconds: 0.001)
}

let snapshot = metrics.snapshot()
SwiftLotusTimer.del(timer)
```

## 🏗 Architecture
*   **SwiftLotus**: The main worker class managing the event loop, socket binding, lifecycle callbacks, and runtime status.
*   **ProtocolInterface**: Defines how raw `ByteBuffer`s are framed, encoded, and decoded. Unopinionated.
*   **Connection**: Represents a client connection, generic over the protocol, with async send, future fast paths, and read backpressure controls.
*   **ConnectionRegistry**: Tracks live connections by id, uid, and group for Workerman-style long-lived services.
*   **RuntimeStateStore / SwiftLotusProcessManager**: Manage worker metadata, status files, CLI process lifecycle, and reload signals.
*   **GatewayRouteTable**: Maintains distributed uid/group route indexes for register-style gateway deployments.
*   **SwiftLotusHTTPClient / SwiftLotusEventBus / SwiftLotusScheduler / SwiftLotusMetrics**: Small v1 ecosystem components for outbound calls, local pub/sub, scheduled tasks, and process-local observability.

## 📄 License

MIT
