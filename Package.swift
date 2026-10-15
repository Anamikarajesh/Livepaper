// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LivePaper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LivePaper", targets: ["LivePaper"])
    ],
    targets: [
        .executableTarget(
            name: "LivePaper",
            path: "Sources/LivePaper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
