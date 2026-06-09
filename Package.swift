// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrainDump",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .executable(name: "BrainDump", targets: ["macOS"]),
    ],
    targets: [
        // Platform-agnostic logic — no AppKit/UIKit/SwiftUI
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release)),
            ]
        ),

        // macOS menu bar app
        .executableTarget(
            name: "macOS",
            dependencies: ["Core"],
            path: "Sources/macOS",
            exclude: ["Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
            ]
        ),

        // iOS placeholder
        .target(
            name: "iOS",
            dependencies: ["Core"],
            path: "Sources/iOS"
        ),
    ]
)
