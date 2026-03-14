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
        .library(name: "OracleControllerShared", targets: ["OracleControllerShared"]),
        .executable(name: "oracle", targets: ["oracle"]),
        .executable(name: "OracleControllerHost", targets: ["OracleControllerHost"]),
        .executable(name: "OracleController", targets: ["OracleController"]),
    ],
    dependencies: [
        // Pin AXorcist to the last working Swift 5.9-compatible revision.
        // Revision a10bbab introduced a broken formatDebugLogMessage reference;
        // cf1d7e3 is the commit immediately before that and compiles cleanly.
        .package(url: "https://github.com/steipete/AXorcist.git", revision: "cf1d7e372a625f4ffabdb938ca3028ae9b8ca7f7"),
    ],
    targets: [
        .target(
            name: "OracleOS",
            dependencies: [
                .product(name: "AXorcist", package: "AXorcist"),
            ],
            path: "Sources/OracleOS",
            swiftSettings: concurrencySettings,
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "OracleControllerShared",
            path: "Sources/OracleControllerShared",
            swiftSettings: concurrencySettings
        ),
        .executableTarget(
            name: "oracle",
            dependencies: ["OracleOS"],
            path: "Sources/oracle",
            swiftSettings: concurrencySettings
        ),
        .executableTarget(
            name: "OracleControllerHost",
            dependencies: ["OracleOS", "OracleControllerShared"],
            path: "Sources/OracleControllerHost",
            swiftSettings: concurrencySettings,
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "OracleController",
            dependencies: ["OracleControllerShared", "OracleOS"],
            path: "Sources/OracleController",
            swiftSettings: concurrencySettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
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
            exclude: ["README.md"],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "OracleControllerTests",
            dependencies: ["OracleControllerShared", "OracleOS"],
            path: "Tests/OracleControllerTests",
            swiftSettings: concurrencySettings
        ),
    ]
)
