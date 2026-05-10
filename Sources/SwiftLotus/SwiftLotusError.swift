import Foundation

public enum SwiftLotusError: Error, Equatable, CustomStringConvertible {
    case invalidURI(String)
    case tlsContextRequired(scheme: String)
    case payloadTooLarge(maximum: Int)

    public var description: String {
        switch self {
        case .invalidURI(let uri):
            return "Invalid URI: \(uri)"
        case .tlsContextRequired(let scheme):
            return "TLS context is required for \(scheme) connections"
        case .payloadTooLarge(let maximum):
            return "Payload exceeds maximum package size of \(maximum) bytes"
        }
    }
}
