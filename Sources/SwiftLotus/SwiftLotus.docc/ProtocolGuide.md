# Protocol Guide

Choose a built-in protocol or implement ``ProtocolInterface`` for a custom TCP wire format.

## Overview

SwiftLotus separates transport lifecycle from message framing. A worker owns the listener and connections; a protocol decides how bytes are split into packets, decoded into application messages, and encoded back to bytes.

Use this guide when deciding between ``TextProtocol``, ``FrameProtocol``, ``HttpProtocol``, ``WebSocketProtocol``, ``DatagramTextProtocol``, or a custom ``ProtocolInterface`` implementation.

## ProtocolInterface Contract

``ProtocolInterface`` defines two associated types:

```swift
associatedtype Message: Sendable
associatedtype Response: Sendable
```

`Message` is delivered to `onMessage`. `Response` is accepted by `connection.send(_:)`.

The default TCP pipeline calls three static methods:

| Method | Responsibility |
| --- | --- |
| `input(buffer:)` | Inspect accumulated bytes and return a complete packet length, or `0` when more bytes are required. |
| `decode(buffer:)` | Convert the complete packet into `Message`. The buffer contains exactly the package returned by `input`. |
| `encode(data:allocator:)` | Convert `Response` into bytes for outbound writes. |

The framework also exposes `addHandlers(pipeline:worker:)` for specialized pipeline integration. Most application protocols should keep the default implementation and provide only `input`, `decode`, and `encode`. ``HttpProtocol`` and ``WebSocketProtocol`` use custom pipeline integration internally.

## Built-In Protocols

| Protocol | Message | Response | Use Case |
| --- | --- | --- | --- |
| ``TextProtocol`` | `String` | `String` | Newline-delimited TCP commands, chat, simple control protocols. |
| ``FrameProtocol`` | `String` | `String` | Length-prefixed TCP messages with a 4-byte big-endian body length. |
| ``HttpProtocol`` | ``HttpRequest`` | ``HttpResponse`` | Small HTTP/1.1 endpoints, health checks, internal APIs. |
| ``WebSocketProtocol`` | ``WebSocketFrameWrapper`` | `String` or ``WebSocketFrameWrapper`` | WebSocket gateways and browser-facing long connections. |
| ``DatagramTextProtocol`` | `String` | `String` | UDP datagram text services through ``SwiftLotusUDP``. |

## TextProtocol

``TextProtocol`` reads until `\n`, strips trailing `\n` and optional `\r`, and writes responses with a trailing newline:

```swift
let worker = SwiftLotus<TextProtocol>(
    name: "LineServer",
    uri: "tcp://0.0.0.0:9000"
)

worker.onMessage = { connection, line in
    try await connection.send("echo: \(line)")
}
```

Use it when clients and servers can exchange line-oriented messages. Avoid it for arbitrary binary payloads.

## FrameProtocol

``FrameProtocol`` uses a 4-byte big-endian length header followed by a UTF-8 string body:

```text
+----------------+------------------+
| UInt32 length   | UTF-8 body bytes |
+----------------+------------------+
```

Use it when messages may contain newlines or when framing should be independent from message content.

## HTTP And WebSocket Protocols

``HttpProtocol`` installs an HTTP/1.1 server pipeline and delivers ``HttpRequest``:

```swift
let api = SwiftLotus<HttpProtocol>(name: "API", uri: "http://0.0.0.0:8080")

api.onMessageSync = { connection, request in
    connection.writeHTTPResponse(HttpResponse(body: "OK"))
}
```

``WebSocketProtocol`` performs WebSocket handling and delivers ``WebSocketFrameWrapper``:

```swift
let gateway = SwiftLotus<WebSocketProtocol>(
    name: "Gateway",
    uri: "websocket://0.0.0.0:8080"
)

gateway.onMessage = { connection, frame in
    try await connection.send("echo: " + frame.string)
}
```

Use HTTP for request/response endpoints. Use WebSocket for browser or gateway connections that must stay open.

## Datagram Protocols

``DatagramTextProtocol`` is used with ``SwiftLotusUDP``:

```swift
let udp = SwiftLotusUDP<DatagramTextProtocol>(
    name: "Stats",
    uri: "udp://0.0.0.0:9000"
)

udp.onMessage = { address, message, server in
    server.send("ack: \(message)", to: address)
}
```

UDP does not provide connection state, ordering, or retries. Application protocols should account for packet loss and duplication.

## Custom TCP Protocol

Implement a custom protocol when the wire format is domain-specific:

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

Important rules:

- `input(buffer:)` must not move the reader index.
- Return `0` when the buffer does not contain a complete packet.
- Return the complete packet length when decoding can proceed.
- Enforce payload limits before allocating large buffers.
- Keep `decode(buffer:)` deterministic and side-effect free.
- Encode every response into the exact wire format expected by the client.

## Custom Pipeline Protocols

`addHandlers(pipeline:worker:)` is an advanced integration point for protocols that require NIO handlers beyond the default byte-to-message and message-to-byte codecs. The built-in HTTP and WebSocket protocols use this path because they need specialized NIO pipeline setup.

For application-defined TCP protocols, prefer implementing `input(buffer:)`, `decode(buffer:)`, and `encode(data:allocator:)`. That keeps connection registration, metrics, lifecycle callbacks, and message dispatch on the standard SwiftLotus path.

## Protocol Selection Checklist

- Use ``TextProtocol`` for human-readable line protocols.
- Use ``FrameProtocol`` when message bodies can contain delimiters.
- Use ``HttpProtocol`` for request/response HTTP endpoints.
- Use ``WebSocketProtocol`` for browser or gateway persistent connections.
- Use ``DatagramTextProtocol`` for UDP text packets.
- Implement ``ProtocolInterface`` for binary protocols, existing proprietary protocols, or protocol-specific payload validation.
- Keep the default pipeline unless the protocol is implemented as part of a custom SwiftLotus transport integration.
