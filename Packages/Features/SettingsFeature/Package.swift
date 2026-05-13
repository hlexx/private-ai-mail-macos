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
        .package(path: "../../Core/Persistence"),
        .package(path: "../../Mail/MailSync"),
        .package(path: "../../Mail/MailProviders"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                "AuthKit",
                "DesignSystem",
                "Persistence",
                "MailSync",
                "MailProviders",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
    ]
)
