# API Reference Guide

Understand the primary SwiftLotus APIs and the responsibility of each runtime surface.

## Overview

SwiftLotus exposes a small set of public APIs around five areas:

- Worker runtime: accepts connections, configures lifecycle hooks, and owns the EventLoop group.
- Connection APIs: send data, close channels, control reads, and track authentication state.
- Registry APIs: bind local connections to user ids and groups.
- Process runtime APIs: start, supervise, reload, stop, and inspect compiled worker executables.
- Gateway APIs: maintain route tables and dispatch delivery envelopes to gateway nodes.

This guide complements the symbol reference. Use it to choose the correct API before drilling into individual symbols.

## Worker Runtime

``SwiftLotus`` is the main worker type. It is generic over a ``ProtocolInterface`` implementation:

```swift
let worker = SwiftLotus<TextProtocol>(
    name: "ChatServer",
    count: 4,
    uri: "tcp://0.0.0.0:2346"
)
```

Key configuration properties:

| API | Purpose |
| --- | --- |
| `name` | Human-readable worker name used in status output and runtime metadata. |
| `count` | Number of EventLoop threads created by this worker. |
| `uri` | Listener URI. Supported schemes include `tcp://`, `http://`, `websocket://`, and `unix://`. |
| `sslContext` | TLS context required by TLS-oriented schemes. |
| `enableSignalHandlers` | Enables built-in signal handling for stop and reload behavior. |
| `reusePort` | Enables multiple workers to bind the same TCP port when the platform supports it. |
| `idleTimeout` | Adds an idle handler and emits ``SwiftLotusIdleEvent``. |
| `closeIdleConnections` | Closes connections automatically after idle events. |
| `writeBufferWaterMark` | Configures NIO write-buffer watermarks for backpressure. |
| `connectionLimits` | Controls max connections, per-IP limits, and authentication timeouts. |
| `reloadable` | Determines whether a worker exits after handling reload. |

Runtime methods:

| API | Purpose |
| --- | --- |
| `run()` | Starts listening and keeps the worker alive until the server channel closes. |
| `stop()` | Closes the server channel and shuts down the worker EventLoop group. |
| `status` | Returns a snapshot suitable for status files and operational checks. |

## Worker Callbacks

Assign callbacks before calling `run()`:

| Callback | When It Runs |
| --- | --- |
| `onWorkerStart` | After the listener has bound successfully. |
| `onWorkerStop` | After the server channel closes. |
| `onWorkerReload` | When the worker receives a reload signal. |
| `onConnect` | After a connection is accepted and registered. |
| `onMessage` | For each decoded inbound message, using async application logic. |
| `onMessageSync` | For tiny non-blocking handlers that should run directly on the channel EventLoop. |
| `onClose` | When a connection becomes inactive. |
| `onError` | When channel or protocol handling reports an error. |
| `onIdle` | When the configured idle timeout fires. |
| `onBufferFull` | When the channel becomes non-writable. |
| `onBufferDrain` | When the channel becomes writable again. |
| `onConnectionRejected` | When connection governance rejects a new channel. |

Use `onMessage` by default. Use `onMessageSync` only when the code is CPU-light, non-blocking, and writes a response immediately.

## Connection APIs

``Connection`` wraps a NIO channel and is generic over the same protocol as the worker.

| API | Purpose |
| --- | --- |
| `id` | Stable UUID for local connection tracking. |
| `remoteAddress` | Remote socket address when available. |
| `isActive` | Whether the underlying channel is active. |
| `isWritable` | Whether the channel is currently writable. |
| `eventLoop` | Channel EventLoop for advanced integration. |
| `isReadPaused` | Whether automatic reads have been paused through SwiftLotus. |
| `isAuthenticated` | Whether `markAuthenticated()` has been called. |
| `send(_:)` | Async send using the protocol's response type. |
| `writeProtocolResponse(_:)` | EventLoop future fast path for writes. |
| `close()` | Async channel close. |
| `closeFuture()` | EventLoop future close path. |
| `pauseRead()` | Sets `autoRead` to `false`. |
| `resumeRead()` | Sets `autoRead` to `true`. |
| `markAuthenticated()` | Marks the connection as authenticated for timeout governance. |

## Registry APIs

Use the worker convenience methods for local uid and group routing:

| API | Purpose |
| --- | --- |
| `bind(_:uid:)` | Associates a connection with one user id. |
| `unbind(_:)` | Removes the user binding for a connection. |
| `join(_:group:)` | Adds a connection to a group. |
| `leave(_:group:)` | Removes a connection from a group. |
| `connections(forUid:)` | Returns local connections for a user id. |
| `connections(inGroup:)` | Returns local connections in a group. |
| `sendToUid(_:_:)` | Sends a response to all local connections for a user id. |
| `sendToGroup(_:_:)` | Sends a response to all local connections in a group. |
| `broadcast(_:)` | Sends a response to all local connections in this worker. |

The registry is process-local. Use the gateway APIs when routing must cross worker or node boundaries.

## Process Runtime APIs

``SwiftLotusProcessManager`` manages compiled executables and runtime state files.

| API | Purpose |
| --- | --- |
| `start(_:)` | Starts the configured number of worker processes. |
| `supervise(_:options:)` | Keeps reconciling worker state and restarts missing workers. |
| `stop(runtimeDirectory:timeout:)` | Sends termination signals and clears runtime state. |
| `restart(_:)` | Stops and starts a worker set. |
| `reload(runtimeDirectory:)` | Sends reload signals to current workers. |
| `rollingReload(_:options:)` | Replaces workers one by one. |
| `status(runtimeDirectory:)` | Reads worker records and status snapshots. |

``WorkerProcessSpec`` describes the executable, arguments, worker count, runtime directory, `reusePort`, and reload behavior.

## Gateway APIs

``GatewayRouteTable`` maintains a routing index:

| API | Purpose |
| --- | --- |
| `register(_:)` | Registers a gateway node. |
| `unregister(nodeId:)` | Removes a node and its routes. |
| `bind(connectionId:uid:nodeId:)` | Binds a connection id to a uid on a node. |
| `unbind(connectionId:uid:)` | Removes a uid route. |
| `join(connectionId:group:nodeId:)` | Adds a connection route to a group. |
| `leave(connectionId:group:)` | Removes a group route. |
| `routes(forUid:)` | Finds uid routes. |
| `routes(inGroup:)` | Finds group routes. |
| `routes(forConnection:)` | Finds direct connection routes. |
| `apply(_:)` | Applies a ``GatewayControlMessage``. |

``GatewayDeliveryPlane`` receives a ``GatewayDeliveryEnvelope`` and invokes an application-supplied async delivery handler for each destination gateway node.

## Client And Component APIs

| API | Purpose |
| --- | --- |
| ``AsyncTcpConnection`` | Maintains an outbound TCP connection with optional reconnect policy. |
| ``SwiftLotusHTTPClient`` | Performs outbound HTTP and HTTPS requests. |
| ``SwiftLotusEventBus`` | Provides in-process topic-based pub/sub. |
| ``SwiftLotusScheduler`` | Schedules interval and daily tasks. |
| ``SwiftLotusMetrics`` | Records counters, gauges, and duration summaries. |
| ``SwiftLotusUDP`` | Runs datagram services with a ``ProtocolInterface`` codec. |

These helpers are intentionally small. Compose them with application-level storage, messaging, and observability systems as needed.
