// ExtensionFetchPolicy.swift
// Limits what an extension's proxied fetch() can reach. The proxy has no CORS, so without
// this an extension could read file:// URLs or call services bound to the device's loopback.

import Foundation
import Darwin

enum ExtensionFetchPolicy {
    /// Session for proxied extension requests; redirects are held to the same policy.
    static let session = URLSession(configuration: .default, delegate: RedirectGuard(), delegateQueue: nil)

    /// Only http(s) to hosts other than this device's loopback, unspecified and link-local
    /// addresses. Private LAN hosts stay reachable for self-hosted indexers.
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return false }
        return !isLocalAddress(numericHost: host)
    }

    /// Parses `host` the way the resolver does (so `127.1` and `2130706433` are caught too).
    /// A name that is not a numeric address is not judged here.
    private static func isLocalAddress(numericHost host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return false }
        defer { freeaddrinfo(info) }

        switch info.pointee.ai_family {
        case AF_INET:
            let address = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            return isLocalIPv4(address)
        case AF_INET6:
            let bytes: [UInt8] = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            if bytes[0..<15].allSatisfy({ $0 == 0 }) { return bytes[15] <= 1 }     // :: and ::1
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }         // fe80::/10
            if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                // IPv4-mapped: judge the embedded address.
                return isLocalIPv4(bytes[12..<16].reduce(0) { $0 << 8 | UInt32($1) })
            }
            return false
        default:
            return false
        }
    }

    private static func isLocalIPv4(_ address: UInt32) -> Bool {
        address >> 24 == 127 || address >> 16 == 0xA9FE || address >> 24 == 0   // 127/8, 169.254/16, 0/8
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Declining hands the 3xx response back instead of following it.
        completionHandler(request.url.map(ExtensionFetchPolicy.allows) == true ? request : nil)
    }
}
