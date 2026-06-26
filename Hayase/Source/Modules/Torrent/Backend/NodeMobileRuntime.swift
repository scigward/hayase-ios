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

enum NodeMobileRuntimeState: Equatable {
    case idle
    case running
    case exited(Int32)
}

enum NodeMobileRuntimeError: LocalizedError {
    case unavailable
    case alreadyStarted
    case exited(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "NodeMobile is not available in this build."
        case .alreadyStarted:
            return "NodeMobile has already been started."
        case .exited(let code):
            return "NodeMobile exited unexpectedly with code \(code). Restart the app before trying the WebTorrent backend again."
        }
    }
}

final class NodeMobileRuntime {
    static let shared = NodeMobileRuntime()

    private let lock = NSLock()
    private var state: NodeMobileRuntimeState = .idle
    private var thread: Thread?

    var currentState: NodeMobileRuntimeState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private init() {}

    func start(scriptURL: URL, arguments: [String]) throws {
        #if !canImport(NodeMobile)
        throw NodeMobileRuntimeError.unavailable
        #endif

        lock.lock()
        switch state {
        case .idle:
            state = .running
        case .running:
            lock.unlock()
            throw NodeMobileRuntimeError.alreadyStarted
        case .exited(let code):
            lock.unlock()
            throw NodeMobileRuntimeError.exited(code)
        }
        lock.unlock()

        let argv = ["node", scriptURL.path] + arguments
        let nodeThread = Thread { [weak self, argv] in
            let exitCode = Self.runNode(argv: argv)
            self?.markExited(exitCode)
        }
        nodeThread.name = "HayaseNodeMobile"
        nodeThread.qualityOfService = .userInitiated
        thread = nodeThread
        nodeThread.start()
    }

    private func markExited(_ code: Int32) {
        lock.lock()
        state = .exited(code)
        thread = nil
        lock.unlock()
    }

    private static func runNode(argv: [String]) -> Int32 {
        #if canImport(NodeMobile)
        var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        defer {
            for pointer in cStrings {
                if let pointer { free(pointer) }
            }
        }
        let argc = Int32(argv.count)
        cStrings.append(nil)
        return cStrings.withUnsafeMutableBufferPointer { buffer in
            node_start(argc, buffer.baseAddress)
        }
        #else
        _ = argv
        return -1
        #endif
    }
}
