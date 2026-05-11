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

**SwiftLotus** 是一个基于 SwiftNIO 的轻量级异步网络服务框架。它不仅可以处理 HTTP 和 WebSocket，也可以作为自定义 TCP 协议、长连接服务、代理服务、游戏网关、IoT 网关等场景的底层网络引擎。

项目提供 Swift 6 `async/await` 风格的易用 API，同时保留 SwiftNIO 的 EventLoop 模型。对于极短的热点路径，也提供同步 EventLoop 快路径，减少不必要的任务调度开销。

## 为什么选择 SwiftLotus？

- **协议可插拔**：通过 `ProtocolInterface` 定义编解码和分包逻辑，可以快速实现文本协议、定长帧协议或自定义二进制协议。
- **面向长连接**：Worker 内置连接管理，可以直接遍历 `worker.connections` 做广播、连接追踪和会话管理。
- **异步优先，保留快路径**：普通业务使用 `onMessage` 编写 async 逻辑；性能敏感的短响应场景可以使用 `onMessageSync` 直接在 EventLoop 上写回。
- **核心包保持精简**：根包只包含网络核心。Redis、MySQL、Postgres 适配器放在 `Addons/` 独立包中，按需引入。
- **安全边界明确**：内置 payload 大小限制、TLS 配置校验和 WebSocket 分片聚合保护，避免常见资源耗尽问题。

## 功能特性

- 基于 SwiftNIO 的 TCP/HTTP/WebSocket 网络处理
- 内置 Text、Frame、HTTP/1.1、WebSocket 协议支持
- Swift 6 并发安全适配，关键共享状态使用 `NIOLock` 保护
- `Connection` 抽象支持 async 发送和 EventLoop future 快路径
- 可选数据库 add-on：Redis、MySQL、Postgres
- NIO EventLoop 定时器封装

## 性能基准

本仓库在 `Benchmarks/HTTP` 中提供一套本机回归压测，用于比较最小化 `SwiftLotus<HttpProtocol>` 服务器和最小化 raw SwiftNIO HTTP 服务器的同机差距。它适合观察框架层开销，不等同于业界排行。

最新本机数据：

```text
压测工具:                        ApacheBench
压测命令:                        ab -n 200000 -c 100 -k
并发级别 (Concurrency Level):      100
总完成请求数 (Complete requests):  200000
失败请求数 (Failed requests):      0

SwiftLotus HTTP:                 80707.74 requests/sec
Raw SwiftNIO HTTP:               82151.65 requests/sec
```

如果要做正式横向对比，建议使用 TechEmpower Framework Benchmarks。TFB 对响应格式、HTTP pipelining、`wrk`、并发等级和硬件环境都有统一要求；本仓库的 benchmark 保持轻量，方便开发阶段快速回归。

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
import SwiftLotus

@main
struct App {
    static func main() async throws {
        let worker = SwiftLotus<TextProtocol>(name: "ChatServer", uri: "tcp://0.0.0.0:2346")

        worker.onConnect = { connection in
            print("Client connected: \(connection.id)")
        }

        worker.onMessage = { connection, message in
            for sibling in worker.connections.values {
                try? await sibling.send("User \(connection.id): \(message)")
            }
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

### 4. Redis add-on 示例

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

### 5. EventLoop 定时器

```swift
let timer = SwiftLotusTimer.add(timeInterval: 1.0) {
    print("Running every second...")
}

// SwiftLotusTimer.del(timer)
```

## 架构

- **SwiftLotus**：管理 EventLoop、监听 socket、连接生命周期和事件回调。
- **ProtocolInterface**：定义原始 `ByteBuffer` 如何分包、解码和编码。
- **Connection**：表示一个客户端连接，按协议泛型化，提供 async 和 future 两种发送方式。

## License

MIT
