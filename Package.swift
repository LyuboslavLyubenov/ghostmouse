// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ghostmouse",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GhostMouseCore",
            path: "Sources/GhostMouseCore"
        ),
        .executableTarget(
            name: "ghostmouse",
            dependencies: ["GhostMouseCore"],
            path: "Sources/ghostmouse",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
        .testTarget(
            name: "GhostMouseCoreTests",
            dependencies: ["GhostMouseCore"],
            path: "Tests/GhostMouseCoreTests"
        ),
        .executableTarget(
            name: "ghostmouse-tests",
            dependencies: ["GhostMouseCore"],
            path: "Sources/ghostmouse-tests"
        )
    ]
)
