// swift-tools-version: 5.3
import PackageDescription

let package = Package(
    name: "WebRTC",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_11),
    ],
    products: [
        .library(name: "WebRTC", targets: ["WebRTC"]),
    ],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/stasel/WebRTC/releases/download/149.0.0/WebRTC-M149.xcframework.zip",
            checksum: "79c5a3e49a68de30a99baabaf5b4c0067dd7a0b66fdd4b8afb8ec337e746abba"
        ),
    ]
)
