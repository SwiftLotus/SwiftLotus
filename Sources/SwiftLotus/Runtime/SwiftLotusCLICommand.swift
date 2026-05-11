import Foundation

public enum SwiftLotusCLIError: Error, Equatable {
    case missingCommand
    case missingValue(String)
    case invalidWorkerCount(String)
    case unsupportedCommand(String)
    case commandRequired
}

public struct WorkerProcessSpec: Equatable, Sendable {
    public let name: String
    public let executable: String
    public let arguments: [String]
    public let workerCount: Int
    public let runtimeDirectory: URL
    public let reusePort: Bool
    public let reloadable: Bool

    public init(
        name: String,
        executable: String,
        arguments: [String] = [],
        workerCount: Int = 1,
        runtimeDirectory: URL = URL(fileURLWithPath: ".swiftlotus"),
        reusePort: Bool = false,
        reloadable: Bool = true
    ) {
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.workerCount = workerCount
        self.runtimeDirectory = runtimeDirectory
        self.reusePort = reusePort
        self.reloadable = reloadable
    }
}

public enum SwiftLotusCLICommand: Equatable, Sendable {
    case start(WorkerProcessSpec)
    case supervise(WorkerProcessSpec)
    case stop(runtimeDirectory: URL)
    case restart(WorkerProcessSpec)
    case rollingReload(WorkerProcessSpec)
    case reload(runtimeDirectory: URL)
    case status(runtimeDirectory: URL)
    case connections(runtimeDirectory: URL)

    public static func parse(_ arguments: [String]) throws -> SwiftLotusCLICommand {
        var parser = ArgumentParser(Array(arguments.dropFirst()))
        guard let command = parser.next() else {
            throw SwiftLotusCLIError.missingCommand
        }

        switch command {
        case "start":
            return .start(try parser.processSpec())
        case "supervise":
            return .supervise(try parser.processSpec())
        case "restart":
            return .restart(try parser.processSpec())
        case "rolling-reload":
            return .rollingReload(try parser.processSpec())
        case "stop":
            return .stop(runtimeDirectory: parser.runtimeDirectory())
        case "reload":
            return .reload(runtimeDirectory: parser.runtimeDirectory())
        case "status":
            return .status(runtimeDirectory: parser.runtimeDirectory())
        case "connections":
            return .connections(runtimeDirectory: parser.runtimeDirectory())
        default:
            throw SwiftLotusCLIError.unsupportedCommand(command)
        }
    }
}

private struct ArgumentParser {
    private var arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard !arguments.isEmpty else { return nil }
        return arguments.removeFirst()
    }

    mutating func runtimeDirectory() -> URL {
        var runtimeDirectory = URL(fileURLWithPath: ".swiftlotus")
        while let argument = next() {
            if argument == "--runtime-dir", let value = next() {
                runtimeDirectory = URL(fileURLWithPath: value)
            }
        }
        return runtimeDirectory
    }

    mutating func processSpec() throws -> WorkerProcessSpec {
        var name = "SwiftLotus"
        var executable: String?
        var commandArguments: [String] = []
        var workerCount = 1
        var runtimeDirectory = URL(fileURLWithPath: ".swiftlotus")
        var reusePort = false
        var reloadable = true

        while let argument = next() {
            switch argument {
            case "--name":
                name = try requiredValue(argument)
            case "--command":
                executable = try requiredValue(argument)
            case "--workers":
                let value = try requiredValue(argument)
                guard let parsed = Int(value), parsed > 0 else {
                    throw SwiftLotusCLIError.invalidWorkerCount(value)
                }
                workerCount = parsed
            case "--runtime-dir":
                runtimeDirectory = URL(fileURLWithPath: try requiredValue(argument))
            case "--reuse-port":
                reusePort = true
            case "--no-reload":
                reloadable = false
            case "--":
                commandArguments.append(contentsOf: arguments)
                arguments.removeAll()
            default:
                commandArguments.append(argument)
            }
        }

        guard let executable else {
            throw SwiftLotusCLIError.commandRequired
        }

        return WorkerProcessSpec(
            name: name,
            executable: executable,
            arguments: commandArguments,
            workerCount: workerCount,
            runtimeDirectory: runtimeDirectory,
            reusePort: reusePort,
            reloadable: reloadable
        )
    }

    mutating private func requiredValue(_ name: String) throws -> String {
        guard let value = next() else {
            throw SwiftLotusCLIError.missingValue(name)
        }
        return value
    }
}
