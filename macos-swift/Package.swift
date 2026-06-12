// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EtcdWorkbenchSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EtcdWorkbenchSwift", targets: ["EtcdWorkbenchSwift"])
    ],
    targets: [
        .executableTarget(
            name: "EtcdWorkbenchSwift",
            path: "Sources/EtcdWorkbenchSwift",
            exclude: ["Info.plist"],
            resources: [
                .process("../../Resources/icon.icns")
            ]
        )
    ]
)
