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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0")
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
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "driftTests",
            dependencies: ["drift"]
        ),
    ],
)
