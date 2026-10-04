//
//  Native.swift
//  Hayase
//
//  Mirrors: src/lib/modules/native.ts, the part of it that tells about the device and the app: what the interface
//  asks its host for in `native.version()`, `native.getDeviceInfo()`, `native.getLogs()` and
//  `native.checkAvailableSpace()`, which the Debug page saves. (The rest of `native` is done where it is used:
//  the media session, the links, the torrent client.)
//

import UIKit

enum Native {
    /// `native.version()`
    static func version() -> String {
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// The build of the app: what `version` of `$app/environment` is for the interface, which is its own build
    static func build() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// `native.getDeviceInfo()`: the device, its system, its screen and what it has of memory and processors
    @MainActor
    static func getDeviceInfo() -> [String: Any] {
        var system = utsname()
        uname(&system)
        let model = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let process = ProcessInfo.processInfo
        let screen = UIScreen.main
        return [
            "platform": "iOS",
            "systemName": UIDevice.current.systemName,
            "systemVersion": UIDevice.current.systemVersion,
            "operatingSystem": process.operatingSystemVersionString,
            "model": model,
            "idiom": UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
            "isiOSAppOnMac": process.isiOSAppOnMac,
            "screen": [
                "width": Double(screen.bounds.width),
                "height": Double(screen.bounds.height),
                "scale": Double(screen.scale),
                "maximumFramesPerSecond": screen.maximumFramesPerSecond,
            ],
            "memoryBytes": process.physicalMemory,
            "processorCount": process.processorCount,
            "activeProcessorCount": process.activeProcessorCount,
            "thermalState": process.thermalState.rawValue,
            "lowPowerMode": process.isLowPowerModeEnabled,
            "locale": Locale.current.identifier,
            "preferredLanguages": Locale.preferredLanguages,
            "timeZone": TimeZone.current.identifier,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
        ]
    }

    /// `native.getLogs()`
    static func getLogs() -> String {
        StreamingLogger.shared.exportText()
    }

    /// `native.checkAvailableSpace()`: the free space of the volume the folder is on, which counts
    /// what the system would give back when it is needed.
    static func checkAvailableSpace(at path: String = TorrentBackendSettings().path) throws -> Int64 {
        var url = URL(fileURLWithPath: path)
        // The folder may not have been made yet: its volume is that of the nearest folder that has.
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
            throw CocoaError(.fileReadUnknown)
        }
        return capacity
    }
}
