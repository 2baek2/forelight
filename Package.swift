// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Forelight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Forelight", targets: ["Forelight"]),
        .executable(name: "forelight-cli", targets: ["forelight-cli"])
    ],
    targets: [
        .executableTarget(
            name: "Forelight"
        ),
        .executableTarget(
            name: "forelight-cli",
            path: "Sources/ForelightCLI"
        ),
        .testTarget(
            name: "ForelightTests",
            dependencies: ["Forelight"]
        )
    ]
)
