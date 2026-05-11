import Foundation
import SwiftLotus

func argumentValue(_ name: String, default defaultValue: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return arguments[index + 1]
}

@main
struct SwiftLotusTCPBenchmarkServer {
    static func main() async throws {
        let host = argumentValue("--host", default: "127.0.0.1")
        let port = argumentValue("--port", default: "8797")
        let worker = SwiftLotus<TextProtocol>(
            name: "SwiftLotusTCPBenchmark",
            uri: "tcp://\(host):\(port)",
            enableSignalHandlers: false
        )

        worker.onMessageSync = { connection, message in
            connection.writeProtocolResponse(message)
        }

        print("READY SwiftLotusTCPBenchmarkServer tcp://\(host):\(port)")
        try await worker.run()
    }
}
