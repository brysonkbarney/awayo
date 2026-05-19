// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Awayo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Awayo",
            targets: ["Awayo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Awayo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
    ]
)
