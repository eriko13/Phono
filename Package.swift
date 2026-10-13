// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "phono",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        // Shared with the iOS app in iOS/.
        .library(name: "PhonoCore", targets: ["PhonoCore"]),
        .library(name: "PhonoKit", targets: ["PhonoKit"])
    ],
    dependencies: [
        // Fermion's runner for Phonon-2 on the Neural Engine (Apache-2.0).
        .package(url: "https://github.com/fermionresearch/phonon-coreml", exact: "1.1.2")
    ],
    targets: [
        // Pure Foundation logic: hotkeys, settings, model files, text.
        // No AppKit or Core ML, so it builds and tests anywhere Swift runs.
        .target(
            name: "PhonoCore",
            path: "Sources/PhonoCore"
        ),
        // Recording and the server client, shared by the Mac and iOS apps.
        .target(
            name: "PhonoKit",
            dependencies: ["PhonoCore"],
            path: "Sources/PhonoKit"
        ),
        // The menu-bar app and the CLI. One binary, two launch modes.
        .executableTarget(
            name: "phono",
            dependencies: [
                "PhonoCore",
                "PhonoKit",
                .product(name: "PhononCoreML", package: "phonon-coreml"),
            ],
            path: "Sources/phono"
        ),
        .testTarget(
            name: "PhonoCoreTests",
            dependencies: ["PhonoCore"],
            path: "Tests/PhonoCoreTests"
        )
    ]
)
