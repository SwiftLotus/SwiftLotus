# 使用指南

本文从安装、TCP 服务开发、连接管理、运行时管理到生产部署，系统说明 SwiftLotus 的主要使用方式。

## 1. 安装

在应用的 `Package.swift` 中加入 SwiftLotus：

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

根包仅包含网络核心。Redis、MySQL、Postgres 适配器位于 `Addons/`，可按需单独引入。

## 2. 创建 TCP 文本服务

``TextProtocol`` 适合按换行符分隔消息的 TCP 服务：

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

        try await worker.run()
    }
}
```

上述示例会启动一个常驻 TCP worker，管理连接生命周期，并通过 group 广播消息。

## 3. 管理连接、用户和分组

每个 ``SwiftLotus`` worker 都内置 ``ConnectionRegistry``，可用于单 worker 内的 uid/group 路由：

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

主要接口：

- `bind(_:uid:)`：把连接绑定到用户 id。
- `join(_:group:)`：把连接加入分组。
- `sendToUid(_:_:)`：向某个 uid 的本地连接发送消息。
- `sendToGroup(_:_:)`：向某个 group 的本地连接发送消息。
- `broadcast(_:)`：向当前 worker 的所有连接发送消息。

## 4. 背压、空闲连接和认证超时

面向公网或高并发长连接服务时，应设置写缓冲水位并在背压过高时暂停读取：

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

空闲连接可通过 NIO idle event 进行清理：

```swift
worker.idleTimeout = .seconds(90)
worker.closeIdleConnections = true

worker.onIdle = { connection, _ in
    print("idle:", connection.id)
}
```

如果协议需要登录态，可启用认证超时，并在认证成功后标记连接：

```swift
worker.connectionLimits.authenticationTimeout = .seconds(10)

worker.onMessage = { connection, message in
    if message == "auth:ok" {
        connection.markAuthenticated()
        try await connection.send("authenticated")
    }
}
```

## 5. 选择 async 回调或 EventLoop 快路径

普通业务逻辑建议使用 `onMessage`，以便调用数据库、上游服务或 actor：

```swift
worker.onMessage = { connection, message in
    let response = try await service.handle(message)
    try await connection.send(response)
}
```

如果热点路径只需要构造小响应并立即写回，可使用 `onMessageSync`，避免为每条消息创建 Swift task：

```swift
let api = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

api.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
```

`onMessageSync` 必须保持非阻塞，不要在里面执行阻塞 IO 或重 CPU 计算。

## 6. WebSocket 和 HTTP

WebSocket 网关可使用 ``WebSocketProtocol``：

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

轻量 HTTP 接口可使用 ``HttpProtocol``：

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

SwiftLotus 的核心是 TCP 连接生命周期和协议分包。HTTP 是内置协议之一，不是完整 MVC Web 框架。

## 7. 自定义协议

非文本协议可通过实现 ``ProtocolInterface`` 接入：

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

`input(buffer:)` 在数据不足时返回 `0`，在完整包可读时返回完整包长度。

## 8. 出站客户端

连接上游 TCP 服务时，可使用 ``AsyncTcpConnection``：

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

发起出站 HTTP 调用时，可使用 ``SwiftLotusHTTPClient``：

```swift
let client = SwiftLotusHTTPClient(requestTimeout: .seconds(5))
let response = try await client.get("http://127.0.0.1:8080/health")
print(response.status, response.body)
```

## 9. 使用 CLI 管理 worker

先构建服务，再用 `swiftlotus` CLI 管理 worker 进程：

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

如需 manager 常驻并自动拉起退出的 worker，可使用 `supervise`：

```bash
.build/release/swiftlotus supervise \
  --name chat \
  --command .build/release/ChatService \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port
```

如需逐个替换 worker，可使用滚动 reload：

```bash
.build/release/swiftlotus rolling-reload \
  --name chat \
  --command .build/release/ChatService \
  --workers 4 \
  --runtime-dir .swiftlotus \
  --reuse-port
```

worker 会收到 `SWIFTLOTUS_WORKER_INDEX`、`SWIFTLOTUS_WORKER_COUNT`、`SWIFTLOTUS_REUSE_PORT`、`SWIFTLOTUS_RUNTIME_DIR` 和 `SWIFTLOTUS_RUNTIME_NAME` 等运行时环境变量。

## 10. Gateway 路由和跨节点投递

``GatewayRouteTable`` 用于维护 gateway 节点、uid 和 group 的路由关系：

```swift
let table = GatewayRouteTable()
table.register(GatewayNode(id: "gateway-a", address: "127.0.0.1:9001"))
table.bind(connectionId: "c1", uid: "alice", nodeId: "gateway-a")
table.join(connectionId: "c1", group: "room-1", nodeId: "gateway-a")
```

``GatewayDeliveryPlane`` 根据 connection、uid、group 或 broadcast 计算目标 gateway 节点：

```swift
let plane = GatewayDeliveryPlane(routes: table) { node, envelope in
    // 通过你的 gateway transport 将 envelope.payload 投递到 node.address。
}

let report = await plane.deliver(
    GatewayDeliveryEnvelope(target: .uid("alice"), payload: "hello")
)

print(report.deliveredCount, report.failures)
```

投递平面负责选节点；真正的节点间传输由应用提供。

## 11. Metrics 和观测

每个 worker 都有进程内 metrics：

```swift
let snapshot = worker.metrics.snapshot()
print(snapshot.counters)
print(snapshot.gauges)
```

SwiftLotus 会记录连接创建/关闭、当前连接数、收发消息数、收发字节数、背压事件和错误数。业务也可写入自定义指标：

```swift
worker.metrics.incrementCounter("jobs.created")
worker.metrics.setGauge("queue.depth", value: 42)
worker.metrics.recordDuration("db.query", seconds: 0.014)
```

生产环境中可定期将 snapshot 导出到自有监控系统。

## 12. 生产部署检查项

上线前建议完成以下检查：

- 为公网 listener 设置 `connectionLimits.maxConnections` 和 `maxConnectionsPerIP`。
- 设置 `authenticationTimeout`，并在登录成功后调用 `markAuthenticated()`。
- 自定义协议要限制 payload 大小，并尽早拒绝异常帧。
- 设置 `idleTimeout`，按业务决定是否启用 `closeIdleConnections`。
- 设置写缓冲水位，并在背压过高时暂停读取。
- 需要自动拉起 worker 时，使用 `supervise`。
- 需要平滑替换 worker 时，使用 `rolling-reload`。
- 对 reloadable worker 使用 `reload` 或 `SIGUSR1` 触发重载。
- 将 `worker.status` 和 `worker.metrics.snapshot()` 接入运维系统。
- 修改协议热路径后，运行 `Benchmarks/TCP` 和 `Benchmarks/HTTP` 执行本地回归压测。

## 13. 本地基准测试

仓库内置轻量 benchmark，用于观察 SwiftLotus 相对 raw SwiftNIO 的框架层开销：

```bash
cd Benchmarks/TCP
swift build -c release

.build/release/SwiftLotusTCPBenchmarkServer
.build/release/TCPBenchmarkClient --connections 100 --requests 200000
```

这些 benchmark 适用于开发阶段回归，不等同于行业排行。正式 HTTP 框架横向对比建议使用 TechEmpower Framework Benchmarks。
