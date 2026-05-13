# 接口说明

本文说明 SwiftLotus 主要公开接口的职责范围、适用场景和使用边界。

## 概述

SwiftLotus 的公开接口可以分为五类：

- Worker 运行时：负责监听、连接生命周期、事件回调和 EventLoop 资源。
- Connection 接口：负责发送数据、关闭连接、读控制和认证状态标记。
- Registry 接口：负责本进程内的 uid/group 连接索引和消息投递。
- Process Runtime 接口：负责启动、守护、reload、停止和查询已编译 worker 进程。
- Gateway 接口：负责维护跨节点路由表，并将投递 envelope 分发到目标 gateway 节点。

本文用于帮助选择正确的接口；具体参数和类型定义可继续查看对应符号页。

## Worker 运行时

``SwiftLotus`` 是核心 worker 类型，按协议泛型化：

```swift
let worker = SwiftLotus<TextProtocol>(
    name: "ChatServer",
    count: 4,
    uri: "tcp://0.0.0.0:2346"
)
```

主要配置项：

| 接口 | 说明 |
| --- | --- |
| `name` | Worker 名称，用于状态输出和运行时元数据。 |
| `count` | 当前 worker 创建的 EventLoop 线程数。 |
| `uri` | 监听地址。支持 `tcp://`、`http://`、`websocket://` 和 `unix://`。 |
| `sslContext` | TLS 场景下使用的 SSL 上下文。 |
| `enableSignalHandlers` | 是否启用内置信号处理。 |
| `reusePort` | 是否启用端口复用，用于多 worker 绑定同一端口。 |
| `idleTimeout` | 配置空闲检测，并触发 ``SwiftLotusIdleEvent``。 |
| `closeIdleConnections` | 空闲事件触发后是否自动关闭连接。 |
| `writeBufferWaterMark` | 配置 NIO 写缓冲水位，用于背压控制。 |
| `connectionLimits` | 配置最大连接数、单 IP 限制和认证超时。 |
| `reloadable` | 决定 worker 处理 reload 后是否退出。 |

运行时方法：

| 接口 | 说明 |
| --- | --- |
| `run()` | 启动监听并保持 worker 运行，直到 server channel 关闭。 |
| `stop()` | 关闭 server channel 并释放当前 worker 的 EventLoopGroup。 |
| `status` | 返回运行状态快照，可用于状态文件和运维检查。 |

## Worker 回调

以下回调应在调用 `run()` 前完成设置：

| 回调 | 触发时机 |
| --- | --- |
| `onWorkerStart` | Listener 绑定成功后触发。 |
| `onWorkerStop` | Server channel 关闭后触发。 |
| `onWorkerReload` | 收到 reload 信号后触发。 |
| `onConnect` | 连接通过治理规则并完成注册后触发。 |
| `onMessage` | 每条消息完成解码后触发，适合 async 业务逻辑。 |
| `onMessageSync` | 在 channel EventLoop 上同步执行，适合极短的非阻塞响应路径。 |
| `onClose` | 连接 inactive 后触发。 |
| `onError` | 协议处理或 channel 报错时触发。 |
| `onIdle` | 达到空闲超时时触发。 |
| `onBufferFull` | Channel 进入不可写状态时触发。 |
| `onBufferDrain` | Channel 恢复可写状态时触发。 |
| `onConnectionRejected` | 连接被治理规则拒绝时触发。 |

默认应使用 `onMessage`。只有在逻辑非常短、无阻塞 IO、无需 await，并且只进行快速写回时，才建议使用 `onMessageSync`。

## Connection 接口

``Connection`` 封装 NIO channel，并与 worker 使用同一个协议泛型。

| 接口 | 说明 |
| --- | --- |
| `id` | 当前进程内的连接 UUID。 |
| `remoteAddress` | 远端 socket 地址。 |
| `isActive` | 底层 channel 是否处于 active 状态。 |
| `isWritable` | 底层 channel 当前是否可写。 |
| `eventLoop` | 连接所属 EventLoop。 |
| `isReadPaused` | 是否已通过 SwiftLotus 暂停自动读取。 |
| `isAuthenticated` | 是否已调用 `markAuthenticated()`。 |
| `send(_:)` | 按协议响应类型异步发送数据。 |
| `writeProtocolResponse(_:)` | 返回 `EventLoopFuture` 的写入快路径。 |
| `close()` | 异步关闭连接。 |
| `closeFuture()` | 返回 `EventLoopFuture` 的关闭接口。 |
| `pauseRead()` | 将 `autoRead` 设置为 `false`。 |
| `resumeRead()` | 将 `autoRead` 设置为 `true`。 |
| `markAuthenticated()` | 将连接标记为已认证。 |

## Registry 接口

Worker 提供本进程内的 uid/group 路由便捷方法：

| 接口 | 说明 |
| --- | --- |
| `bind(_:uid:)` | 将连接绑定到一个用户 id。 |
| `unbind(_:)` | 移除连接的用户绑定。 |
| `join(_:group:)` | 将连接加入一个分组。 |
| `leave(_:group:)` | 将连接移出指定分组。 |
| `connections(forUid:)` | 获取指定 uid 的本地连接。 |
| `connections(inGroup:)` | 获取指定 group 的本地连接。 |
| `sendToUid(_:_:)` | 向指定 uid 的本地连接发送消息。 |
| `sendToGroup(_:_:)` | 向指定 group 的本地连接发送消息。 |
| `broadcast(_:)` | 向当前 worker 的所有本地连接发送消息。 |

Registry 只覆盖当前进程。需要跨 worker 或跨节点投递时，应使用 Gateway 相关接口。

## Process Runtime 接口

``SwiftLotusProcessManager`` 用于管理已编译的 worker 可执行文件和运行时状态目录。

| 接口 | 说明 |
| --- | --- |
| `start(_:)` | 按配置启动一组 worker 进程。 |
| `supervise(_:options:)` | 持续校验 worker 状态，并自动拉起缺失进程。 |
| `stop(runtimeDirectory:timeout:)` | 发送终止信号并清理运行时状态。 |
| `restart(_:)` | 停止后重新启动 worker。 |
| `reload(runtimeDirectory:)` | 向当前 worker 发送 reload 信号。 |
| `rollingReload(_:options:)` | 按 worker 顺序逐个替换进程。 |
| `status(runtimeDirectory:)` | 读取 worker 记录和状态快照。 |

``WorkerProcessSpec`` 用于描述可执行文件、参数、worker 数量、运行时目录、端口复用和 reload 行为。

## Gateway 接口

``GatewayRouteTable`` 维护 gateway 路由索引：

| 接口 | 说明 |
| --- | --- |
| `register(_:)` | 注册 gateway 节点。 |
| `unregister(nodeId:)` | 移除节点及其相关路由。 |
| `bind(connectionId:uid:nodeId:)` | 将连接 id 绑定到指定 uid 和节点。 |
| `unbind(connectionId:uid:)` | 移除 uid 路由。 |
| `join(connectionId:group:nodeId:)` | 将连接路由加入 group。 |
| `leave(connectionId:group:)` | 移除 group 路由。 |
| `routes(forUid:)` | 查询 uid 路由。 |
| `routes(inGroup:)` | 查询 group 路由。 |
| `routes(forConnection:)` | 查询指定连接路由。 |
| `apply(_:)` | 应用一个 ``GatewayControlMessage``。 |

``GatewayDeliveryPlane`` 接收 ``GatewayDeliveryEnvelope``，根据目标类型计算目标节点，并调用应用提供的异步投递闭包。

## 客户端和组件接口

| 接口 | 说明 |
| --- | --- |
| ``AsyncTcpConnection`` | 维护出站 TCP 连接，可配置重连策略。 |
| ``SwiftLotusHTTPClient`` | 发起出站 HTTP/HTTPS 请求。 |
| ``SwiftLotusEventBus`` | 提供进程内 topic 发布订阅。 |
| ``SwiftLotusScheduler`` | 提供 interval 和 daily 任务调度。 |
| ``SwiftLotusMetrics`` | 记录 counter、gauge 和 duration summary。 |
| ``SwiftLotusUDP`` | 使用 ``ProtocolInterface`` 编解码 datagram 服务。 |

这些组件保持轻量设计。生产应用可按需接入外部存储、消息队列和监控系统。
