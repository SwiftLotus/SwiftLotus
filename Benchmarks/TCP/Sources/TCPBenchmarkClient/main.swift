import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOConcurrencyHelpers

func argumentValue(_ name: String, default defaultValue: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

final class BenchmarkState: @unchecked Sendable {
    private let lock = NIOLock()
    private let done = DispatchSemaphore(value: 0)
    private var sent = 0
    private var completed = 0
    private var startedAt: UInt64 = 0

    let targetRequests: Int

    init(targetRequests: Int) {
        self.targetRequests = targetRequests
    }

    func start() {
        lock.withLock {
            sent = 0
            completed = 0
            startedAt = DispatchTime.now().uptimeNanoseconds
        }
    }

    func reserveSend() -> Bool {
        lock.withLock {
            guard sent < targetRequests else { return false }
            sent += 1
            return true
        }
    }

    func recordResponse() -> Bool {
        lock.withLock {
            completed += 1
            if completed == targetRequests {
                done.signal()
            }
            return sent < targetRequests
        }
    }

    func wait() -> (completed: Int, elapsedSeconds: Double) {
        done.wait()
        return lock.withLock {
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            return (completed, Double(elapsedNanoseconds) / 1_000_000_000)
        }
    }
}

final class PingPongClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let state: BenchmarkState
    private let request: String
    private var buffer = ByteBuffer()

    init(state: BenchmarkState, request: String) {
        self.state = state
        self.request = request
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)
        buffer.writeBuffer(&inbound)

        while let newlineIndex = buffer.readableBytesView.firstIndex(of: 10) {
            let length = newlineIndex - buffer.readerIndex + 1
            guard buffer.readSlice(length: length) != nil else { break }
            if state.recordResponse(), state.reserveSend() {
                let outbound = context.channel.allocator.buffer(string: request)
                context.write(wrapOutboundOut(outbound), promise: nil)
            }
        }

        context.flush()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

@main
struct TCPBenchmarkClient {
    static func main() async throws {
        let host = argumentValue("--host", default: "127.0.0.1")
        let port = Int(argumentValue("--port", default: "8797")) ?? 8797
        let connections = Int(argumentValue("--connections", default: "100")) ?? 100
        let requests = Int(argumentValue("--requests", default: "200000")) ?? 200000
        let message = argumentValue("--message", default: "ping")
        let request = "\(message)\n"

        guard requests >= connections else {
            throw BenchmarkClientError.requestsMustBeAtLeastConnections
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let state = BenchmarkState(targetRequests: requests)
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(PingPongClientHandler(state: state, request: request))
            }

        var channels: [Channel] = []
        channels.reserveCapacity(connections)
        for _ in 0..<connections {
            channels.append(try await bootstrap.connect(host: host, port: port).get())
        }

        state.start()
        for channel in channels {
            if state.reserveSend() {
                let buffer = channel.allocator.buffer(string: request)
                channel.writeAndFlush(buffer, promise: nil)
            }
        }

        let result = state.wait()
        let requestsPerSecond = Double(result.completed) / result.elapsedSeconds
        let averageLatencyMilliseconds = result.elapsedSeconds * 1000 / Double(result.completed) * Double(connections)

        print("TCP benchmark complete")
        print("Host: \(host)")
        print("Port: \(port)")
        print("Connections: \(connections)")
        print("Complete requests: \(result.completed)")
        print("Failed requests: 0")
        print(String(format: "Time taken for tests: %.3f seconds", result.elapsedSeconds))
        print(String(format: "Requests per second: %.2f [#/sec] (mean)", requestsPerSecond))
        print(String(format: "Time per request: %.3f [ms] (mean)", averageLatencyMilliseconds))

        for channel in channels {
            try? await channel.close().get()
        }
        try await group.shutdownGracefully()
    }
}

enum BenchmarkClientError: Error {
    case requestsMustBeAtLeastConnections
}
