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
        .library(name: "PhonoCore", targets: ["PhonoCore"])
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
        // The menu-bar app and the CLI. One binary, two launch modes.
        .executableTarget(
            name: "phono",
            dependencies: [
                "PhonoCore",
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
