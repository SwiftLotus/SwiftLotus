import Foundation
import SwiftLotus

@main
struct SwiftLotusCLI {
    static func main() throws {
        let command = try SwiftLotusCLICommand.parse(CommandLine.arguments)
        let manager = SwiftLotusProcessManager()

        switch command {
        case .start(let spec):
            let state = try manager.start(spec)
            print("Started \(state.records.count) worker(s)")
        case .stop(let runtimeDirectory):
            try manager.stop(runtimeDirectory: runtimeDirectory)
            print("Stopped workers")
        case .restart(let spec):
            let state = try manager.restart(spec)
            print("Restarted \(state.records.count) worker(s)")
        case .reload(let runtimeDirectory):
            try manager.reload(runtimeDirectory: runtimeDirectory)
            print("Reload signal sent")
        case .status(let runtimeDirectory):
            let rows = try manager.status(runtimeDirectory: runtimeDirectory)
            print("pid\tworker\tidx\talive\tconnections\turi")
            for row in rows {
                let status = row.runtimeStatus
                print("\(row.record.pid)\t\(row.record.name)\t\(row.record.workerIndex)\t\(row.isAlive)\t\(status?.connectionCount ?? 0)\t\(status?.uri ?? "-")")
            }
        case .connections(let runtimeDirectory):
            let rows = try manager.status(runtimeDirectory: runtimeDirectory)
            let total = rows.reduce(0) { $0 + ($1.runtimeStatus?.connectionCount ?? 0) }
            print("Total connections: \(total)")
            for row in rows {
                print("\(row.record.name)[\(row.record.workerIndex)] pid=\(row.record.pid) connections=\(row.runtimeStatus?.connectionCount ?? 0)")
            }
        }
    }
}
