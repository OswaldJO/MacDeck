import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum LocalNetworkAddress {
    /// First non-loopback IPv4 address (typical Wi‑Fi IP for companion manual entry).
    static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = ptr?.pointee {
            defer { ptr = interface.ifa_next }
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            guard isUp, isRunning, interface.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            guard let ifaName = interface.ifa_name,
                  let name = String(validatingCString: ifaName) else { continue }
            if name == "lo0" { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0,
               let ip = stringFromNullTerminatedUTF8(hostname),
               !ip.hasPrefix("127.") {
                return ip
            }
        }
        return nil
    }

    private static func stringFromNullTerminatedUTF8(_ bytes: [CChar]) -> String? {
        guard let end = bytes.firstIndex(of: 0), end > 0 else { return nil }
        return String(decoding: bytes[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
