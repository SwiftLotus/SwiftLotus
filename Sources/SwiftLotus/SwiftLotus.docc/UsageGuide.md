# Usage Guide

Learn how to install SwiftLotus, build TCP services, manage connections, operate workers, and prepare a service for production.

## 1. Install The Package

Add SwiftLotus to the application package:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatService",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ChatService",
            dependencies: [
                .product(name: "SwiftLotus", package: "SwiftLotus"),
            ]
        )
    ]
)
```

The root package contains the networking core. Database adapters live under `Addons/` and can be added only when the application needs them.

## 2. Build A TCP Text Service

Use ``TextProtocol`` when each inbound message is a newline-delimited string:

```swift
import NIOCore
import SwiftLotus

@main
struct App {
    static func main() async throws {
        let worker = SwiftLotus<TextProtocol>(
            name: "ChatServer",
            uri: "tcp://0.0.0.0:2346"
        )

        worker.idleTimeout = .seconds(60)
        worker.closeIdleConnections = true
        worker.writeBufferWaterMark = .init(
            low: 1 * 1024 * 1024,
            high: 2 * 1024 * 1024
        )

        worker.onConnect = { connection in
            print("connected:", connection.id)
        }

        worker.onMessage = { connection, message in
            if message.hasPrefix("/uid ") {
                worker.bind(connection, uid: String(message.dropFirst(5)))
                return
            }

            worker.join(connection, group: "lobby")
            try await worker.sendToGroup(
                "lobby",
                "user \(connection.id): \(message)"
            )
        }

        worker.onClose = { connection in
            print("closed:", connection.id)
        }

        try await worker.run()
    }
}
```

This creates a long-running TCP worker, tracks active connections, binds users to ids, and broadcasts messages to a group.

## 3. Use Connection Registry APIs

Every ``SwiftLotus`` worker has a ``ConnectionRegistry``. Use it for single-worker user and group routing:

```swift
worker.onMessage = { connection, message in
    switch message {
    case "/join":
        worker.join(connection, group: "room-1")
        try await connection.send("joined room-1")
    case "/leave":
        worker.leave(connection, group: "room-1")
        try await connection.send("left room-1")
    default:
        _ = try await worker.sendToGroup("room-1", message)
    }
}
```

Use `bind(_:uid:)` for user-oriented routing, `join(_:group:)` for group-oriented routing, and `broadcast(_:)` when every local connection should receive a message.

## 4. Handle Backpressure And Idle Connections

Set write-buffer watermarks and pause reads when outbound pressure is high:

```swift
worker.writeBufferWaterMark = .init(
    low: 512 * 1024,
    high: 2 * 1024 * 1024
)

worker.onBufferFull = { connection in
    connection.pauseRead()
}

worker.onBufferDrain = { connection in
    connection.resumeRead()
}
```

Use idle events to close inactive connections:

```swift
worker.idleTimeout = .seconds(90)
worker.closeIdleConnections = true

worker.onIdle = { connection, _ in
    print("idle:", connection.id)
}
```

For protocols that require authentication, configure a timeout and mark the connection once authentication succeeds:

```swift
worker.connectionLimits.authenticationTimeout = .seconds(10)

worker.onMessage = { connection, message in
    if message == "auth:ok" {
        connection.markAuthenticated()
        try await connection.send("authenticated")
    }
}
```

## 5. Choose Async Or EventLoop Fast Path

Use `onMessage` for normal application work. It supports async calls to databases, upstream services, and other actors:

```swift
worker.onMessage = { connection, message in
    let response = try await service.handle(message)
    try await connection.send(response)
}
```

Use `onMessageSync` only for tiny, non-blocking handlers that should stay on the channel EventLoop:

```swift
let api = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

api.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
```

Do not perform blocking IO, CPU-heavy work, or long awaits from the sync fast path.

## 6. Serve WebSocket And HTTP

Use ``WebSocketProtocol`` for WebSocket gateways:

```swift
let ws = SwiftLotus<WebSocketProtocol>(
    name: "Gateway",
    uri: "websocket://0.0.0.0:8080"
)

ws.onMessage = { connection, frame in
    try await connection.send("echo: " + frame.string)
}

try await ws.run()
```

Use ``HttpProtocol`` for small HTTP endpoints:

```swift
let http = SwiftLotus<HttpProtocol>(
    name: "Health",
    uri: "http://0.0.0.0:8081"
)

http.onMessageSync = { connection, request in
    if request.uri == "/health" {
        connection.writeHTTPResponse(HttpResponse(body: "OK"))
    } else {
        connection.writeHTTPResponse(HttpResponse(status: .notFound, body: "Not Found"))
    }
}

try await http.run()
```

HTTP is a built-in protocol, not the only framework focus. For full MVC-style web applications, compose SwiftLotus with application-level routing and storage layers.

## 7. Define A Custom Protocol

Implement ``ProtocolInterface`` when the wire format is not newline text or built-in frame encoding:

```swift
import NIOCore
import SwiftLotus

struct LengthPrefixedJSON: ProtocolInterface {
    typealias Message = ByteBuffer
    typealias Response = ByteBuffer

    static func input(buffer: inout ByteBuffer) throws -> Int {
        guard buffer.readableBytes >= 4 else { return 0 }
        guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else {
            return 0
        }
        return 4 + Int(length)
    }

    static func decode(buffer: inout ByteBuffer) -> ByteBuffer {
        _ = buffer.readInteger(as: UInt32.self)
        return buffer
    }

    static func encode(data: ByteBuffer, out: inout ByteBuffer) {
        var body = data
        out.writeInteger(UInt32(body.readableBytes))
        out.writeBuffer(&body)
    }
}
```

`input(buffer:)` must return `0` when more bytes are needed. Return the complete packet length when a full message is available.

## 8. Run Outbound Clients

Use ``AsyncTcpConnection`` when a worker needs a persistent upstream TCP connection:

```swift
let upstream = AsyncTcpConnection<TextProtocol>(
    uri: "tcp://127.0.0.1:9000",
    reconnectPolicy: .fixedDelay(maxAttempts: nil, delay: .seconds(1))
)

upstream.onConnect = { connection in
    try await connection.send("hello")
}

upstream.onMessage = { _, message in
    print("upstream:", message)
}

upstream.connect()
```

Use ``SwiftLotusHTTPClient`` for outbound HTTP calls:

```swift
let client = SwiftLotusHTTPClient(requestTimeout: .seconds(5))
let response = try await client.get("http://127.0.0.1:8080/health")
print(response.status, response.body)
```

## 9. Operate Workers With The CLI

Build the service and use the bundled `swiftlotus` executable to manage worker processes:

```bash
swift build -c release

.build/release/swiftlotus start \
  --name chat \
  --command .build/release/ChatService \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port

.build/release/swiftlotus status --runtime-dir .swiftlotus
.build/release/swiftlotus connections --runtime-dir .swiftlotus
.build/release/swiftlotus reload --runtime-dir .swiftlotus
.build/release/swiftlotus stop --runtime-dir .swiftlotus
```

Use `supervise` when the manager process should keep watching child workers and restart exited workers:

```bash
.build/release/swiftlotus supervise \
  --name chat \
  --command .build/release/ChatService \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port
```

Use rolling reload when workers should be replaced one at a time:

```bash
.build/release/swiftlotus rolling-reload \
  --name chat \
  --command .build/release/ChatService \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port
```

Workers receive runtime environment variables such as `SWIFTLOTUS_WORKER_INDEX`, `SWIFTLOTUS_WORKER_COUNT`, `SWIFTLOTUS_REUSE_PORT`, `SWIFTLOTUS_RUNTIME_DIR`, and `SWIFTLOTUS_RUNTIME_NAME`.

## 10. Add Gateway Routing

Use ``GatewayRouteTable`` to maintain uid and group routes across gateway nodes:

```swift
let table = GatewayRouteTable()
table.register(GatewayNode(id: "gateway-a", address: "127.0.0.1:9001"))
table.bind(connectionId: "c1", uid: "alice", nodeId: "gateway-a")
table.join(connectionId: "c1", group: "room-1", nodeId: "gateway-a")
```

Use ``GatewayDeliveryPlane`` to route delivery envelopes to the gateway node responsible for a connection, uid, group, or broadcast:

```swift
let plane = GatewayDeliveryPlane(routes: table) { node, envelope in
    // Send envelope.payload to node.address through your gateway transport.
}

let report = await plane.deliver(
    GatewayDeliveryEnvelope(target: .uid("alice"), payload: "hello")
)

print(report.deliveredCount, report.failures)
```

The delivery plane chooses destination nodes. Your application supplies the transport that sends the envelope to each gateway node.

## 11. Collect Metrics

Each worker exposes process-local metrics:

```swift
let snapshot = worker.metrics.snapshot()
print(snapshot.counters)
print(snapshot.gauges)
```

SwiftLotus records built-in counters and gauges for accepted and closed connections, current connection count, received and sent messages, received and sent bytes, backpressure events, and errors. Applications can add their own metrics:

```swift
worker.metrics.incrementCounter("jobs.created")
worker.metrics.setGauge("queue.depth", value: 42)
worker.metrics.recordDuration("db.query", seconds: 0.014)
```

Export snapshots to the monitoring backend used by your application.

## 12. Production Checklist

Before deploying a SwiftLotus service, check the following:

- Set `connectionLimits.maxConnections` and `maxConnectionsPerIP` for public listeners.
- Set `authenticationTimeout` and call `markAuthenticated()` after login.
- Set payload limits in custom protocols and reject oversized frames early.
- Configure `idleTimeout` and decide whether `closeIdleConnections` should be enabled.
- Configure write-buffer watermarks and pause or resume reads on buffer pressure.
- Prefer `supervise` for long-running deployments that need worker auto-restart.
- Prefer `rolling-reload` for zero-downtime replacement when the listener supports `reusePort`.
- Send `SIGUSR1` or use `reload` for reloadable workers.
- Export `worker.status` and `worker.metrics.snapshot()` to operational tooling.
- Run local TCP and HTTP benchmark suites after changing hot protocol paths.

## 13. Benchmark Locally

The repository includes small regression benchmark packages under `Benchmarks/TCP` and `Benchmarks/HTTP`. They compare SwiftLotus with minimal raw SwiftNIO servers on the same machine:

```bash
cd Benchmarks/TCP
swift build -c release

.build/release/SwiftLotusTCPBenchmarkServer
.build/release/TCPBenchmarkClient --connections 100 --requests 200000
```

These benchmarks measure local framework overhead. They are not industry rankings. For formal HTTP framework comparison, use TechEmpower Framework Benchmarks.
