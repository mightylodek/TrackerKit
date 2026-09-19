// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrackerKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "TrackerKit",
            targets: ["TrackerKit"]
        )
    ],
    targets: [
        .target(
            name: "TrackerKit",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TrackerKitTests",
            dependencies: ["TrackerKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
