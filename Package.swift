// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TwoRelay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TwoRelay", targets: ["TwoRelayApp"]),
        .library(name: "TwoRelayCore", targets: ["TwoRelayCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "TwoRelayCore",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TwoRelayCore"
        ),
        .executableTarget(
            name: "TwoRelayApp",
            dependencies: [
                "TwoRelayCore"
            ],
            path: "Sources/TwoRelayApp"
        ),
        .testTarget(
            name: "TwoRelayAppTests",
            dependencies: ["TwoRelayApp"],
            path: "Tests/TwoRelayAppTests"
        )
    ]
)
