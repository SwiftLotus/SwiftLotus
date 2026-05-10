import Foundation
import NIOHTTP1
import SwiftLotus

func argumentValue(_ name: String, default defaultValue: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

@main
struct SwiftLotusHTTPBenchmarkServer {
    static func main() async throws {
        let host = argumentValue("--host", default: "127.0.0.1")
        let port = argumentValue("--port", default: "8787")
        let worker = SwiftLotus<HttpProtocol>(
            name: "SwiftLotusHTTPBenchmark",
            uri: "http://\(host):\(port)",
            enableSignalHandlers: false
        )

        worker.onMessageSync = { connection, request in
            var headers = HTTPHeaders()
            headers.add(name: "Connection", value: request.head.isKeepAlive ? "keep-alive" : "close")
            connection.writeHTTPResponse(
                HttpResponse(body: "OK", headers: headers),
                closeAfterFlush: !request.head.isKeepAlive
            )
        }

        print("READY SwiftLotusHTTPBenchmarkServer http://\(host):\(port)")
        try await worker.run()
    }
}
