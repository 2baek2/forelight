// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Forelight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Forelight", targets: ["Forelight"])
    ],
    targets: [
        .executableTarget(
            name: "Forelight"
        ),
        .testTarget(
            name: "ForelightTests",
            dependencies: ["Forelight"]
        )
    ]
)
