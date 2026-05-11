@preconcurrency import NIOCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum SwiftLotusSocketOptions {
    static var reusePort: ChannelOptions.Types.SocketOption? {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux)
        return .socket(SocketOptionLevel(SOL_SOCKET), SocketOptionName(SO_REUSEPORT))
        #else
        return nil
        #endif
    }
}
