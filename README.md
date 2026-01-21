
![SwiftLotus](icon.png)

</a>

<p align="center">
    <a href="http://opensource.org/licenses/MIT">
        <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat" alt="MIT License">
    </a>
    <a href="https://github.com/SwiftLotus/SwiftLotus/actions/workflows/swift.yml">
        <img src="https://img.shields.io/github/actions/workflow/status/SwiftLotus/SwiftLotus/swift.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration">
    </a>
    <a href="https://swift.org">
        <img src="https://design.vapor.codes/images/swift60up.svg" alt="Swift 6.0+">
    </a>
</p>

<br>

**SwiftLotus** is a high-performance, asynchronous event-driven network application framework for Swift. It is built from the ground up using **SwiftNIO** and **Swift Structured Concurrency** to leverage modern Swift features.

SwiftLotus allows you to build scalable network applications (TCP/UDP, HTTP, WebSocket, etc.) with a remarkably simple API.

## Features

- **High Performance**: Built on top of Apple's SwiftNIO (Event-driven, Non-blocking I/O).
- **Modern Swift**: Fully utilizes `async/await` and Structured Concurrency.
- **Multi-Protocol**: Built-in support for TCP, HTTP, WebSocket, Text, and Frame protocols.
- **Cross-Platform**: Runs on macOS, Linux, and Windows (Experimental).
- **SSL/TLS**: Native SSL support.
- **Async Client**: Includes `AsyncTcpConnection` for connecting to remote servers asynchronously.
- **Timer**: Built-in high-precision timer.
- **Simple API**: Easy to learn declarative syntax.

## Documentation

Full API documentation is available at [SwiftLotus Documentation](https://swiftlotus.github.io/SwiftLotus/documentation/swiftlotus/).

## Requirements

- Swift 6.0+
- macOS 14+ or Linux (Ubuntu 20.04+, Amazon Linux 2, etc.)
- Windows 10/11 (Experimental)

## Environment Setup

### macOS
1. Install **Xcode** from the Mac App Store.
2. Verify installation: `swift --version`.
3. If you see a sandbox error during build, run: `swift build --disable-sandbox`.

### Linux (Ubuntu 20.04+)
1. Install dependencies:
   ```bash
   sudo apt-get update
   sudo apt-get install binutils git gnupg2 libc6-dev libcurl4 libedit2 libgcc-9-dev libpython2.7 libsqlite3-0 libstdc++-9-dev libxml2 libz3-dev pkg-config tzdata zlib1g-dev
   ```
2. Download and install the Swift Toolchain from [swift.org](https://www.swift.org/download/).

### Windows
1. Install **Swift for Windows** from [swift.org](https://www.swift.org/download/).
2. Install **Visual Studio 2022** with "Desktop development with C++" workload.
3. Use `Command Prompt` (x64 Native Tools Command Prompt is recommended) or PowerShell to run.
   ```powershell
   swift run
   ```
   *Note: Signal handling (Ctrl+C) is currently limited on Windows.*

## Installation

Add SwiftLotus to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/SwiftLotus/SwiftLotus.git", from: "1.0.0"),
]
```

## Basic Usage

### 1. TCP Text Server

A simple echo server using the `TextProtocol` (newline separated).

```swift
import SwiftLotus

@main
struct App {
    static func main() async throws {
        // Create a Worker listening on port 2346
        let worker = SwiftLotus<TextProtocol>(name: "ChatServer", uri: "tcp://0.0.0.0:2346")
        
        // Emitted when a connection is established
        worker.onConnect = { connection in
            print("New connection from \(connection.remoteAddress?.description ?? "unknown")")
        }
        
        // Emitted when data is received
        worker.onMessage = { connection, data in
            print("Received: \(data)")
            // Send response back
            try? await connection.send("Hello " + data)
        }
        
        // Emitted when connection is closed
        worker.onClose = { connection in
            print("Connection closed")
        }
        
        // Run the worker
        try await worker.run()
    }
}
```

### 2. HTTP Server

```swift
import SwiftLotus

let worker = SwiftLotus<HttpProtocol>(name: "WebServer", uri: "http://0.0.0.0:8080")

worker.onMessage = { connection, request in
    // Access Query Parameters
    let name = request.query["name"] ?? "Guest"
    
    // Create Response
    var response = HttpResponse(body: "Hello, \(name)!")
    response.setCookie(name: "visited", value: "true")
    
    try? await connection.send(response)
}

try await worker.run()
```

### 3. WebSocket Server

```swift
import SwiftLotus

let worker = SwiftLotus<WebSocketProtocol>(name: "WSServer", uri: "websocket://0.0.0.0:8080")

worker.onMessage = { connection, frame in
    print("Received: \(frame.string)")
    try? await connection.send("Echo: " + frame.string)
}

try await worker.run()
```

### 4. Async TCP Client

Connect to remote servers asynchronously.

```swift
let client = AsyncTcpConnection<TextProtocol>(uri: "tcp://127.0.0.1:2346")

client.onConnect = { connection in
    print("Connected to server")
    try? await connection.send("Login")
}

client.onMessage = { connection, message in
    print("Received from server: \(message)")
}

client.connect()
```

### 5. Timer

Execute tasks periodically.

```swift
// Run every 2.5 seconds
SwiftLotusTimer.add(timeInterval: 2.5) {
    print("Tick...")
}
```

## Supported Protocols

- **TextProtocol**: Strings separated by newline (`\n`).
- **FrameProtocol**: Length-prefixed binary/text data (4-byte header).
- **HttpProtocol**: Standard HTTP/1.1 server.
- **WebSocketProtocol**: RFC 6455 WebSocket server.

## Architecture

*   **SwiftLotus**: The main worker class managing the event loop and lifecycle.
*   **ProtocolInterface**: Defines how data is framed, encoded, and decoded.
*   **Connection**: Represents a client connection, generic over the protocol.

## License

MIT
