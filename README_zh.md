<p align="center">
  <img src="icon.png" width="200" alt="SwiftLotus Logo">
</p>

# SwiftLotus 🪷

<p align="center">
    <a href="README.md">English</a> | <b>中文版</b>
</p>

<p align="center">
    <a href="http://opensource.org/licenses/MIT">
        <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat" alt="MIT License">
    </a>
    <a href="https://swift.org">
        <img src="https://design.vapor.codes/images/swift60up.svg" alt="Swift 6.0+">
    </a>
</p>

**SwiftLotus** 是一个基于 SwiftNIO 的轻量级异步 TCP 网络服务框架。它的定位更接近 Workerman，而不是传统 HTTP MVC 框架：进程常驻、事件驱动、面向连接生命周期，并允许你在同一套核心之上构建 TCP 服务、自定义协议、WebSocket 网关、代理服务、游戏网关、IoT 网关和 HTTP 接口。

项目提供 Swift 6 `async/await` 风格的易用 API，同时保留 SwiftNIO 的 EventLoop 模型。对于极短的热点路径，也提供同步 EventLoop 快路径，减少不必要的任务调度开销。

## 为什么选择 SwiftLotus？

- **协议可插拔**：通过 `ProtocolInterface` 定义编解码和分包逻辑，可以实现文本协议、定长帧协议或自定义二进制协议。
- **面向 TCP 长连接**：Worker 内置连接管理，可以通过 `worker.connections` 或 uid/group 注册表做广播、连接追踪和会话管理。
- **异步优先，保留快路径**：普通业务使用 `onMessage` 编写 async 逻辑；性能敏感的短响应场景可以使用 `onMessageSync` 直接在 EventLoop 上写回。
- **背压和心跳清理**：支持 write-buffer 水位、暂停/恢复读取，以及基于 NIO idle event 的空闲连接关闭。
- **HTTP 是内置协议，不是唯一核心**：HTTP 和 WebSocket 开箱可用，但 SwiftLotus 的核心仍然是 TCP 连接生命周期、协议分包和事件派发。
- **核心包保持精简**：根包只包含网络核心。Redis、MySQL、Postgres 适配器放在 `Addons/` 独立包中，按需引入。
- **安全边界明确**：内置 payload 大小限制、TLS 配置校验和 WebSocket 分片聚合保护，避免常见资源耗尽问题。

## 功能特性

- 基于 SwiftNIO 的 TCP 网络处理，内置 HTTP/WebSocket 协议支持
- 内置 Text、Frame、HTTP/1.1、WebSocket 协议支持
- Swift 6 并发安全适配，关键共享状态使用 `NIOLock` 保护
- `Connection` 抽象支持 async 发送和 EventLoop future 快路径
- 单机连接注册表：支持绑定 uid、加入 group、按用户发送、按分组发送和广播
- 运行时生命周期回调：`onWorkerStart`、`onWorkerStop`、`onError`、`onIdle`、`onBufferFull`、`onBufferDrain`
- 运行状态快照：可读取 worker 名称、URI、线程数、运行状态、启动时间和当前连接数
- `AsyncTcpConnection` 支持当前连接句柄和固定间隔自动重连策略
- 可选数据库 add-on：Redis、MySQL、Postgres
- NIO EventLoop 定时器封装

### 与 Workerman 的能力边界

SwiftLotus 现在覆盖了 Workerman 风格长连接应用最核心的单进程能力：生命周期回调、连接追踪、uid/group 路由、空闲连接清理、发送背压、定时器、自定义协议和异步 TCP 出站连接。它目前还没有实现 Workerman 的 master/worker 多进程管理、CLI `status/reload` 命令、UDP/Unix Socket 监听，以及 GatewayWorker 那种分布式连接路由。

## 性能基准

本仓库在 `Benchmarks/TCP` 和 `Benchmarks/HTTP` 中提供本机回归压测，用于比较最小化 SwiftLotus 服务和最小化 raw SwiftNIO 服务的同机差距。它适合观察框架层开销，不等同于业界排行。

最新 TCP 文本 echo 数据：

```text
压测工具:                        TCPBenchmarkClient
压测命令:                        --connections 100 --requests 200000
连接数 (Connections):             100
总完成请求数 (Complete requests):  200000
失败请求数 (Failed requests):      0

SwiftLotus TCP:                  80048.22 messages/sec
Raw SwiftNIO TCP:                82205.91 messages/sec
```

HTTP 专项压测仍保留在 `Benchmarks/HTTP` 中。如果要做正式 HTTP 横向对比，建议使用 TechEmpower Framework Benchmarks。TFB 对响应格式、HTTP pipelining、`wrk`、并发等级和硬件环境都有统一要求；本仓库的 benchmark 保持轻量，方便开发阶段快速回归。

## 环境要求

- Swift 6.0+
- macOS 14+ 或 Linux

## 安装

在项目的 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),
]
```

### 按需模块

根包只包含核心网络引擎。数据库适配器位于 `Addons/` 独立包中，可以本地 path 引入，也可以拆成独立仓库发布：

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),

    // 本仓库内本地开发：
    // .package(path: "Addons/SwiftLotusRedis")

    // 独立发布后可使用各自仓库 URL：
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

## 快速开始

### 1. TCP 文本协议服务

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
            print("Client connected: \(connection.id)")
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
            try? await worker.sendToGroup("lobby", "User \(connection.id): \(message)")
        }

        try await worker.run()
    }
}
```

### 2. WebSocket 服务

```swift
import SwiftLotus

let worker = SwiftLotus<WebSocketProtocol>(name: "WSServer", uri: "websocket://0.0.0.0:8080")

worker.onMessage = { connection, frame in
    try? await connection.send("Echo: " + frame.string)
}

try await worker.run()
```

### 3. EventLoop 快路径

普通业务逻辑建议使用 `onMessage`。如果处理器只需要组装并写出一个很小的响应，可以使用 `onMessageSync`，它会直接在 channel 所属 EventLoop 上执行，避免每条消息额外创建 Swift task。这个回调中不要执行阻塞计算或阻塞 IO。

```swift
let worker = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

worker.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
```

### 4. 带重连的异步 TCP 客户端

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

### 5. Redis add-on 示例

```swift
import SwiftLotus
import SwiftLotusRedis
import RediStack

@main
struct App {
    static func main() async throws {
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

### 6. EventLoop 定时器

```swift
let timer = SwiftLotusTimer.add(timeInterval: 1.0) {
    print("Running every second...")
}

// SwiftLotusTimer.del(timer)
```

## 架构

- **SwiftLotus**：管理 EventLoop、监听 socket、连接生命周期、事件回调和运行状态。
- **ProtocolInterface**：定义原始 `ByteBuffer` 如何分包、解码和编码。
- **Connection**：表示一个客户端连接，按协议泛型化，提供 async 发送、future 快路径和读背压控制。
- **ConnectionRegistry**：按连接 id、uid、group 追踪在线连接，服务于 Workerman 风格长连接应用。

## License

MIT
