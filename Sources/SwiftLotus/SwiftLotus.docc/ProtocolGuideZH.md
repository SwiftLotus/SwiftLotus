# 协议使用说明

本文说明如何选择内置协议，以及如何通过 ``ProtocolInterface`` 实现自定义 TCP 协议。

## 概述

SwiftLotus 将传输层生命周期和消息协议分离。Worker 负责监听、连接管理和事件派发；协议负责将字节流切分为完整消息、将消息解码为业务对象，并将响应编码为字节。

当需要在 ``TextProtocol``、``FrameProtocol``、``HttpProtocol``、``WebSocketProtocol``、``DatagramTextProtocol`` 和自定义协议之间做选择时，可参考本文。

## ProtocolInterface 契约

``ProtocolInterface`` 定义两个关联类型：

```swift
associatedtype Message: Sendable
associatedtype Response: Sendable
```

`Message` 是传递给 `onMessage` 的入站消息类型。`Response` 是 `connection.send(_:)` 接收的出站响应类型。

默认 TCP pipeline 会调用以下三个静态方法：

| 方法 | 职责 |
| --- | --- |
| `input(buffer:)` | 检查累积字节；如果已有完整包，返回完整包长度；如果还需要更多数据，返回 `0`。 |
| `decode(buffer:)` | 将完整包解码为 `Message`。传入 buffer 的长度等于 `input` 返回的包长度。 |
| `encode(data:allocator:)` | 将 `Response` 编码为出站字节。 |

框架同时暴露 `addHandlers(pipeline:worker:)`，用于专用 pipeline 集成。大多数应用自定义协议应保留默认实现，只提供 `input`、`decode` 和 `encode`。``HttpProtocol`` 和 ``WebSocketProtocol`` 在框架内部使用了自定义 pipeline 集成。

## 内置协议选择

| 协议 | 入站类型 | 出站类型 | 适用场景 |
| --- | --- | --- | --- |
| ``TextProtocol`` | `String` | `String` | 按换行符分隔的 TCP 命令、聊天消息、控制协议。 |
| ``FrameProtocol`` | `String` | `String` | 4 字节大端长度头 + body 的定长帧协议。 |
| ``HttpProtocol`` | ``HttpRequest`` | ``HttpResponse`` | HTTP/1.1 接口、健康检查、内部管理 API。 |
| ``WebSocketProtocol`` | ``WebSocketFrameWrapper`` | `String` 或 ``WebSocketFrameWrapper`` | WebSocket 网关、浏览器长连接。 |
| ``DatagramTextProtocol`` | `String` | `String` | 基于 ``SwiftLotusUDP`` 的 UDP 文本 datagram 服务。 |

## TextProtocol

``TextProtocol`` 读取到 `\n` 为止，解码时会移除末尾 `\n` 和可选的 `\r`，编码响应时会自动追加换行符：

```swift
let worker = SwiftLotus<TextProtocol>(
    name: "LineServer",
    uri: "tcp://0.0.0.0:9000"
)

worker.onMessage = { connection, line in
    try await connection.send("echo: \(line)")
}
```

该协议适用于行协议。对于任意二进制 payload，不建议使用该协议。

## FrameProtocol

``FrameProtocol`` 使用 4 字节大端长度头，后面跟随 UTF-8 字符串 body：

```text
+----------------+------------------+
| UInt32 length   | UTF-8 body bytes |
+----------------+------------------+
```

当消息内容可能包含换行符，或者希望 framing 与内容解耦时，应优先考虑该协议。

## HTTP 和 WebSocket 协议

``HttpProtocol`` 会安装 HTTP/1.1 server pipeline，并向业务层传递 ``HttpRequest``：

```swift
let api = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

api.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
```

``WebSocketProtocol`` 负责 WebSocket frame 处理，并向业务层传递 ``WebSocketFrameWrapper``：

```swift
let gateway = SwiftLotus<WebSocketProtocol>(
    name: "Gateway",
    uri: "websocket://0.0.0.0:8080"
)

gateway.onMessage = { connection, frame in
    try await connection.send("echo: " + frame.string)
}
```

HTTP 适用于请求/响应模型。WebSocket 适用于需要保持连接的浏览器或网关场景。

## Datagram 协议

``DatagramTextProtocol`` 与 ``SwiftLotusUDP`` 配合使用：

```swift
let udp = SwiftLotusUDP<DatagramTextProtocol>(
    name: "Stats",
    uri: "udp://0.0.0.0:9000"
)

udp.onMessage = { address, message, server in
    server.send("ack: \(message)", to: address)
}
```

UDP 不提供连接状态、顺序保证或重试机制。应用层协议应自行处理丢包、重复和乱序问题。

## 自定义 TCP 协议

当业务使用专有二进制格式或需要特殊 payload 校验时，可以实现自定义协议：

```swift
import NIOCore
import SwiftLotus

struct BinaryCommandProtocol: ProtocolInterface {
    struct Message: Sendable {
        let command: UInt8
        let body: ByteBuffer
    }

    typealias Response = ByteBuffer

    static func input(buffer: inout ByteBuffer) throws -> Int {
        guard buffer.readableBytes >= 5 else { return 0 }
        guard let bodyLength = buffer.getInteger(
            at: buffer.readerIndex + 1,
            as: UInt32.self
        ) else {
            return 0
        }

        let totalLength = 1 + 4 + Int(bodyLength)
        if totalLength > 1024 * 1024 {
            throw SwiftLotusError.payloadTooLarge(maximum: 1024 * 1024)
        }

        return buffer.readableBytes >= totalLength ? totalLength : 0
    }

    static func decode(buffer: inout ByteBuffer) -> Message {
        let command = buffer.readInteger(as: UInt8.self) ?? 0
        let bodyLength = Int(buffer.readInteger(as: UInt32.self) ?? 0)
        let body = buffer.readSlice(length: bodyLength) ?? ByteBuffer()
        return Message(command: command, body: body)
    }

    static func encode(data: ByteBuffer, allocator: ByteBufferAllocator) -> ByteBuffer {
        var body = data
        var out = allocator.buffer(capacity: 5 + body.readableBytes)
        out.writeInteger(UInt8(1))
        out.writeInteger(UInt32(body.readableBytes))
        out.writeBuffer(&body)
        return out
    }
}
```

实现自定义协议时应遵守以下规则：

- `input(buffer:)` 不应移动 reader index。
- 数据不足时返回 `0`。
- 数据完整时返回完整包长度。
- 分配大块内存前应先做 payload 大小校验。
- `decode(buffer:)` 应保持确定性，避免外部副作用。
- `encode(data:allocator:)` 应严格输出客户端期望的 wire format。

## 自定义 Pipeline 协议

`addHandlers(pipeline:worker:)` 是高级集成点，适用于默认 byte-to-message 和 message-to-byte 编解码流程无法覆盖的协议。内置 HTTP 和 WebSocket 协议使用该路径，是因为它们需要专用的 NIO pipeline 组合。

应用侧自定义 TCP 协议应优先实现 `input(buffer:)`、`decode(buffer:)` 和 `encode(data:allocator:)`。这样可以继续使用 SwiftLotus 标准路径中的连接注册、metrics、生命周期回调和消息派发。

## 协议选择建议

- 行文本协议使用 ``TextProtocol``。
- 消息体可能包含分隔符时使用 ``FrameProtocol``。
- 请求/响应 HTTP 接口使用 ``HttpProtocol``。
- 浏览器或 gateway 长连接使用 ``WebSocketProtocol``。
- UDP 文本 datagram 使用 ``DatagramTextProtocol``。
- 专有二进制协议、既有协议适配或特殊 payload 校验场景，实现 ``ProtocolInterface``。
- 除非正在实现自定义 SwiftLotus transport 集成，否则应保留默认 pipeline。
