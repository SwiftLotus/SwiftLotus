# SwiftLotus

Build long-running TCP services, custom protocols, WebSocket gateways, and lightweight HTTP endpoints on top of SwiftNIO.

## Overview

SwiftLotus is a protocol-oriented networking framework for applications that need persistent connections, event-driven workers, and explicit connection lifecycle control. HTTP and WebSocket are included as built-in protocols, but the core model is TCP: define how bytes become messages, attach lifecycle callbacks, and run one or more workers as long-lived processes.

Use SwiftLotus when you need:

- TCP or Unix socket services with custom framing.
- WebSocket gateways and connection registries.
- Long-lived worker processes with reload, supervision, and status files.
- Backpressure, idle connection cleanup, connection limits, and lightweight metrics.
- Small ecosystem helpers such as outbound TCP clients, HTTP clients, event bus, timers, and schedulers.

Start with <doc:UsageGuide> for an end-to-end guide from installation to production operation.

## Topics

### Guides

- <doc:UsageGuide>
- <doc:UsageGuideZH>

### Core Server Runtime

- ``Connection``
- ``ProtocolInterface``
- ``TextProtocol``
- ``FrameProtocol``
- ``HttpProtocol``
- ``WebSocketProtocol``

### Connection Management

- ``ConnectionRegistry``
- ``ConnectionLimits``
- ``ConnectionGovernor``
- ``ConnectionDecision``
- ``SwiftLotusIdleEvent``

### Process Runtime

- ``SwiftLotusProcessManager``
- ``WorkerProcessSpec``
- ``RuntimeStateStore``
- ``SwiftLotusRuntimeEnvironment``
- ``SwiftLotusCLICommand``

### Gateway Routing

- ``GatewayRouteTable``
- ``GatewayDeliveryPlane``
- ``GatewayControlMessage``
- ``GatewayNode``
- ``GatewayRoute``

### Clients And Components

- ``AsyncTcpConnection``
- ``SwiftLotusHTTPClient``
- ``SwiftLotusEventBus``
- ``SwiftLotusScheduler``
- ``SwiftLotusMetrics``
- ``SwiftLotusUDP``
