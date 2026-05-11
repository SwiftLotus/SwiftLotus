# TCP Benchmarks

This package keeps TCP benchmark code outside the core SwiftLotus package. It compares a minimal `SwiftLotus<TextProtocol>` line echo server with a minimal raw SwiftNIO TCP line echo server on the same machine.

## Scope

This is a local regression benchmark for TCP protocol overhead. It is not an industry benchmark and should not be compared directly with HTTP benchmark results.

The benchmark client opens N persistent TCP connections. Each connection sends a newline-delimited `ping` message, waits for the echoed line, then sends the next message until the requested total is reached.

Latest local run:

```text
Connections:            100
Complete requests:      200000
Failed requests:        0

SwiftLotus TCP:         80048.22 messages/sec
Raw SwiftNIO TCP:       82205.91 messages/sec
```

## Build

```bash
cd Benchmarks/TCP
xcrun swift build -c release
```

## Run

Start one server at a time:

```bash
cd Benchmarks/TCP
.build/release/SwiftLotusTCPBenchmarkServer --host 127.0.0.1 --port 8797
.build/release/NIOTCPBenchmarkServer --host 127.0.0.1 --port 8798
```

Then run the benchmark client from another terminal:

```bash
.build/release/TCPBenchmarkClient --host 127.0.0.1 --port 8797 --connections 100 --requests 200000
.build/release/TCPBenchmarkClient --host 127.0.0.1 --port 8798 --connections 100 --requests 200000
```

Use the raw NIO result as the local upper-bound reference. SwiftLotus should stay close for line-delimited echo workloads; larger gaps usually indicate framework overhead in decoding, event dispatch, or response encoding.
