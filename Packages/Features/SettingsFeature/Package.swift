// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../../Auth/AuthKit"),
        .package(path: "../../Core/DesignSystem"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                "AuthKit",
                "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
    ]
)
