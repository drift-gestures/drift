// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TouchX",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TouchX", targets: ["TouchX"])
    ],
    targets: [
        .target(
            name: "TouchXMultitouch",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("dl")
            ]
        ),
        .executableTarget(
            name: "TouchX",
            dependencies: ["TouchXMultitouch"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "TouchXTests",
            dependencies: ["TouchX"]
        )
    ]
)
