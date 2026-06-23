// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WhatsLive",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhatsLive", targets: ["WhatsLive"])
    ],
    targets: [
        .executableTarget(
            name: "WhatsLive",
            path: "Sources/WhatsLive"
        ),
        .testTarget(
            name: "WhatsLiveTests",
            dependencies: ["WhatsLive"],
            path: "Tests/WhatsLiveTests"
        )
    ]
)
