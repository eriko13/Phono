// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "phono",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        // Pure Foundation logic: WAV encoding, the engine's HTTP protocol,
        // settings, and engine discovery. No AppKit, so it builds and tests
        // anywhere Swift runs.
        .target(
            name: "PhonoCore",
            path: "Sources/PhonoCore"
        ),
        // The menu-bar app and the CLI. One binary, two launch modes.
        .executableTarget(
            name: "phono",
            dependencies: ["PhonoCore"],
            path: "Sources/phono"
        ),
        .testTarget(
            name: "PhonoCoreTests",
            dependencies: ["PhonoCore"],
            path: "Tests/PhonoCoreTests"
        )
    ]
)
