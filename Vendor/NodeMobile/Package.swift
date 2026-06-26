// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "NodeMobile",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(name: "NodeMobile", targets: ["NodeMobile"]),
    ],
    targets: [
        .binaryTarget(
            name: "NodeMobile",
            url: "https://github.com/heylogin/nodejs-mobile/releases/download/v24.5.0-mobile/nodejs-mobile-v24.5.0-ios.zip",
            checksum: "b3c515c451ed45d3a58915efe426e3cb9ac7debb56f649ddd62d871d97b2da9e"
        ),
    ]
)
