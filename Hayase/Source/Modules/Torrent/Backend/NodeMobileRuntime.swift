//
//  NodeMobileRuntime.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

#if canImport(NodeMobile)
import Darwin
import NodeMobile
#endif

enum NodeMobileRuntimeError: LocalizedError {
    case unavailable
    case alreadyStarted

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "NodeMobile is not available in this build."
        case .alreadyStarted:
            return "NodeMobile has already been started."
        }
    }
}

final class NodeMobileRuntime {
    static let shared = NodeMobileRuntime()

    private let lock = NSLock()
    private var started = false
    private var thread: Thread?

    private init() {}

    func start(scriptURL: URL, arguments: [String]) throws {
        #if !canImport(NodeMobile)
        throw NodeMobileRuntimeError.unavailable
        #endif

        lock.lock()
        defer { lock.unlock() }

        guard !started else { throw NodeMobileRuntimeError.alreadyStarted }
        started = true

        let argv = ["node", scriptURL.path] + arguments
        let nodeThread = Thread { [argv] in
            Self.runNode(argv: argv)
        }
        nodeThread.name = "HayaseNodeMobile"
        nodeThread.qualityOfService = .userInitiated
        thread = nodeThread
        nodeThread.start()
    }

    private static func runNode(argv: [String]) {
        #if canImport(NodeMobile)
        var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        defer {
            for pointer in cStrings {
                if let pointer { free(pointer) }
            }
        }
        let argc = Int32(argv.count)
        cStrings.append(nil)
        _ = cStrings.withUnsafeMutableBufferPointer { buffer in
            node_start(argc, buffer.baseAddress)
        }
        #else
        _ = argv
        #endif
    }
}
