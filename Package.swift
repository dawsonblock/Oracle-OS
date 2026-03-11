// swift-tools-version: 5.9

import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "OracleOS",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "OracleOS", targets: ["OracleOS"]),
        .executable(name: "oracle", targets: ["oracle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/AXorcist.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "OracleOS",
            dependencies: [
                .product(name: "AXorcist", package: "AXorcist"),
            ],
            path: "Sources/OracleOS",
            swiftSettings: concurrencySettings,
            linkerSettings: [.linkedFramework("ScreenCaptureKit")]
        ),
        .executableTarget(
            name: "oracle",
            dependencies: ["OracleOS"],
            path: "Sources/oracle",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "OracleOSTests",
            dependencies: ["OracleOS"],
            path: "Tests/OracleOSTests",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "OracleOSEvals",
            dependencies: ["OracleOS"],
            path: "Tests/OracleOSEvals",
            swiftSettings: concurrencySettings
        ),
    ]
)
