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

**SwiftLotus** 是一款基于 Swift 打造的开源、超高性能、异步非阻塞的底层 Socket 引擎。它不仅能提供处理基础 HTTP 与 WebSocket 的能力，更是一个极其通用且灵活的网络通信骨架。您可以使用它轻松开发百万级并发的长连接 TCP 代理、大规模分布式游戏服务器后台、物联网 (IoT) 设备的自定义私有协议网关，以及任何需要极高吞吐量与实时双向交互的网络服务集群。

它完全基于 Apple 官方的顶级强力非阻塞网络架构 **SwiftNIO** 构建，并深度融合了 Swift 6 极度安全的**结构化并发 (`async/await`)** 原生特性。在为您提供直达物理网卡极限的裸流吞吐能力的同时，保持了声明式且优美的 API 设计。

## 🚀 为什么选择 SwiftLotus？

SwiftLotus 提供了一种回归本源的极速事件通讯骨架：
- **真正的零开销 (Zero Overhead)**：没有任何强制的协议包袱，原生暴露出底层的 TCP/UDP 字节流。支持任意插拔的解析协议，一切损耗降至冰点。
- **天生为状态驻留设计 (Stateful)**：管理上万长连接是它的原生天赋。需要在一个接口内瞬间向全服 10,000 名在线玩家群发广播消息？只需直接遍历全局的 `worker.connections` 池即可瞬间脱卷发送完毕。
- **底层多核压榨 (True Shared-Threading)**：整个 App 的所有外网连接、甚至内外部数据库的每一次 I/O 调用，都严格复用并共享着同一个极速的 C 语言级核心调度环 (`GlobalEventLoop` / epoll / kqueue)，直接从物理层面消除掉多线程环境的上下文切换成本。
- **按需加载的大型生态 (On-Demand)**：自带工业级网络与数据库装载器。我们提供了高度解耦的按需微模块（独立原生整合 `Redis`, `MySQL`, `Postgres`）。如果您不需要用到某个存储层组件，您就永远不用下载哪怕一行它的无关庞杂代码！

## 📦 核心硬核特性
- **性能永不妥协**: 站在巨人的肩膀上，实现网络读写全程零线程上下文切换 (Zero Context Switch)。
- **严苛的并发安全**: 完美兼容最新的 Swift 6 并发安全标准 (Strict Concurrency)，底层全部使用 `NIOLock` 互斥锁与 `@Sendable` 完全闭合了任意可能的数据争抢漏洞。
- **OOM 爆破防护**: 内置最强悍的 TCP Payload Size 安全防御涂层 (被动式 Memory Shields，防大包穿透)。
- **开箱即用的原生协议**: 直接内嵌原生裸 TCP 流、基础 HTTP/1.1、RFC 标准 WebSocket、Text 换行符分割协议以及基于二进制的前置定长 Frame 协议。
- **极速按需数据库**: 采用包目标物理隔离式 (Target Isolation) 支持了 `RediStack`、`MySQLNIO`、`PostgresNIO` 级并发。
- **超高精度物理调度器**: 纯原生依托于 NIO 发动机的物理级别高精度 EventLoop 定时器 (完美避开低效的 `Task.sleep` 携程睡眠消耗)。

## ⚡️ 物理性能压测指标
采用原生 `SwiftLotus<HttpProtocol>` 作为纯文本的 Ping-Pong 微服务器。在**彻底关闭 Keep-Alive 连接保持机制（强制每一个独立请求都要进行完整的 TCP 三次握手建联、发包、回包再到立即四次挥手断开回收）**的最残酷极端压测环境下，一台普通的家用局域网非优化的本地机器依旧以亚毫秒级的极限延迟跑出了 **> 10,000+ RPS** 的惊人吞吐。如果您是在高防长连接 (`wrk -c`) 的常规网关形态下，吞吐表现将会呈指数级飞跃并直线撞击网卡的物理处理上限天花板！

```text
并发级别 (Concurrency Level):      100
总完成请求数 (Complete requests):  20000
失败请求数 (Failed requests):      0
每秒处理请求 (Requests per second): 10496.17 [#/sec] (平均)
单服务器请求消耗 (Time per request): 0.095 [ms] (平均并发分布)
```
*(上述数据使用 Apache Bench 通过 `ab -c 100 -n 20000` 在本机实测得出)*

## 🛠 开发环境要求

- Swift 6.0 或以上
- macOS 14+ 或 Linux (Ubuntu 20.04+, Amazon Linux 2 等全部主流发行版)

## 📦 快速安装 (SPM引入)

在您项目的 `Package.swift` 依赖树中直接添加：

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),
]
```

### 生态微模块按需自选装载 (Target Splitting)
为了保持您工程依赖库的极致精简，所有重型的三方数据库驱动均采用严格的按需挂载方案。按您自己所需的实际组件进行挂载组装：
```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftLotus", package: "SwiftLotus"),          // 【必选】核心网络发动机引擎 (无任何无关杂项)
            .product(name: "SwiftLotusRedis", package: "SwiftLotus"),     // Redis 高频集成
            .product(name: "SwiftLotusMySQL", package: "SwiftLotus"),     // MySQL 原生连接器
            // .product(name: "SwiftLotusPostgres", package: "SwiftLotus") // Postgres 连接器
        ]
    )
]
```

## ⏱ 五分钟极速部署指南 (Quick Start)

### 1. 简易弹幕/IM 极速后台服务 (带原生 TCP 群广播)
没有多余中间件！原生自带全服玩家连接池，仅用二十行带起一个并发上万的群聊内核：

```swift
import SwiftLotus

@main
struct App {
    static func main() async throws {
        // 利用极简 Text 协议 (基于\n换行符) 在 2346 物理端口启动服务
        let worker = SwiftLotus<TextProtocol>(name: "ChatServer", uri: "tcp://0.0.0.0:2346")
        
        // 生命周期：上线拦截
        worker.onConnect = { connection in
            print("玩家成功潜入网络，分配物理身份 ID: \(connection.id)")
        }
        
        // 核心事件：数据吞吐
        worker.onMessage = { connection, message in
            // API：极速取出全服在线字典 `connections.values` 瞬间进行数据面全图广播分发
            worker.connections.values.forEach { sibling in 
                try? await sibling.send("玩家 \(connection.id) 说: \(message)")
            }
        }
        
        try await worker.run()
    }
}
```

### 2. 纯血高性能 WebSocket 游戏通信节点
天生自带协议簇免配置解析/组帧分发特性，以及不可破圈的 Payload 防爆破 OOM 反伤防御安全涂层。

```swift
import SwiftLotus

// 换个网络协议标记 `WebSocketProtocol`，服务立马变身
let worker = SwiftLotus<WebSocketProtocol>(name: "WSServer", uri: "websocket://0.0.0.0:8080")

worker.onMessage = { connection, frame in
    // 框架底层早已为您全自动执行了掩码转换，直接取字符串用
    try? await connection.send("服务器收到您的消息: " + frame.string)
}

try await worker.run()
```

### 3. C 语言系统级原生的零挂载等待数据库联动 (例: Redis)
在 SwiftLotus 中，您的每一次极其高频的外部数据库请求和发包动作都会被胶水模块自动挂载到与底层发报机同样的系统 `EventLoop` 下（这称之为真正的物理级别跨 IO 零切换开销机制 Zero Context Switching！）

```swift
import SwiftLotus
import SwiftLotusRedis

@main
struct App {
    static func main() async throws {
        // 第一步：一键激活！自动生成跨界融合绑定着共享原生调度轮盘的 `RediStack` 全局高频请求连接池
        try SwiftLotusRedis.setup(hostname: "127.0.0.1", port: 6379)
        
        let worker = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")
        
        worker.onMessage = { connection, request in
            // 用最新的 struct 协程执行法，绝对不会给 SwiftNIO 调度主核造成哪怕一微秒的同步 Block 卡顿！！
            let count = try await SwiftLotusRedis.pool.increment(RedisKey("views")).get()
            
            // 数据下发
            try await connection.send(HttpResponse(body: "页面总冷访问量为： \(count)"))
        }
        
        try await worker.run()
    }
}
```

### 4. 系统底层级纳秒定时器
```swift
// 此闭包绝对不使用常规的 Swift 底层 `Task.sleep` 协程睡眠打盹！
// 它的原理等同 C 语言底层操作，直接塞到 `EventLoop` 微秒时间轮中等待系统时钟跳断中断！达到最高最精确的长稳调度器。
let timer = SwiftLotusTimer.add(timeInterval: 1.0) {
    print("这行字将以机器级精度，精准地按照每秒滴答一次...")
}

// 可立刻关闭摘除该闹钟事件:
// SwiftLotusTimer.del(timer)
```

## 🏗 底层架构灵魂三绝 (Architecture)
*   **`SwiftLotus (The EngineWorker)`**: 整个框架驱动的网络大脑与跳动心脏 (核心引擎实体)。它内部自下而上彻底接管和封装所有的底层轮询大循环，管控收揽所有的物理端子监听与新老连接进出吞吐。且原生内置了系统级 `@Sendable` 完全高并发安全的泛型群连接追踪防漏池！
*   **`ProtocolInterface`**: 这是一把用于把您的任意异质客户端所抛出的数据封解尺。规定了一切不按规矩发来的网络乱包杂包怎样才能完美地规避切分漏洞、防抖、防粘包而自动转换重装的边界接口。当它足够标准，没有任何人能干烂您的逻辑层！
*   **`Connection`**: 服务器与对端设备之间被虚拟化了的一根不可见的长管道。它的内存生存周期与 `Worker` 同步且相互互斥绑定监控。(无论是在异端 Actor 中穿插处理它还是怎样，都不存在任何安全警告漏洞读写并发数据安全阻断错误)。

## 📄 开源许可证明 (License)

开源发布基准： MIT
