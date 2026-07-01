// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "drift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "drift", targets: ["drift"])
    ],
    targets: [
        .target(
            name: "driftMultitouch",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("dl")
            ]
        ),
        .executableTarget(
            name: "drift",
            dependencies: ["driftMultitouch"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "driftTests",
            dependencies: ["drift"]
        )
    ]
)
