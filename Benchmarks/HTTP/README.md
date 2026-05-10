# HTTP Benchmarks

This package keeps benchmark code outside the core SwiftLotus package so normal users do not pay for benchmark-only targets.

## Servers

- `SwiftLotusHTTPBenchmarkServer`: minimal `SwiftLotus<HttpProtocol>` server returning `OK`.
- `NIOHTTPBenchmarkServer`: minimal raw SwiftNIO HTTP server returning `OK`.

## Scope

This is a local regression benchmark, not an industry benchmark. It is useful for checking SwiftLotus overhead against raw SwiftNIO on the same machine.

For industry-style comparisons, use TechEmpower Framework Benchmarks (TFB). TFB plaintext tests use stricter response requirements, HTTP pipelining, `wrk`, much higher concurrency levels, and controlled physical/cloud hardware. Treat this package as a quick smoke test before building or submitting a TFB-compatible benchmark.

TFB is not run from this package directly. To run an official-style benchmark, add a SwiftLotus implementation under the TechEmpower `FrameworkBenchmarks` repository, provide the framework metadata and Docker setup, then run only that test with TFB's toolchain before attempting a full matrix run.

## Build

```bash
cd Benchmarks/HTTP
xcrun swift build -c release
```

## Run

Start one server at a time:

```bash
cd Benchmarks/HTTP
.build/release/SwiftLotusHTTPBenchmarkServer --host 127.0.0.1 --port 8787
.build/release/NIOHTTPBenchmarkServer --host 127.0.0.1 --port 8788
```

Then run ApacheBench from another terminal:

```bash
ab -n 200000 -c 100 -k http://127.0.0.1:8787/
ab -n 200000 -c 100 -k http://127.0.0.1:8788/
```

Use the raw NIO result as the local upper-bound reference. SwiftLotus should be close to it for tiny HTTP responses; larger gaps usually indicate framework overhead in task dispatch, protocol bridging, or response framing.
