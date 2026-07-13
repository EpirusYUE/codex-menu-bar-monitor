// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexMenuBar", targets: ["CodexMenuBar"])
    ],
    targets: [
        .target(
            name: "CodexStatusCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "CodexMenuBar",
            dependencies: ["CodexStatusCore"]
        ),
        .testTarget(
            name: "CodexStatusCoreTests",
            dependencies: ["CodexStatusCore"]
        )
    ]
)
