// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InboxFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InboxFeature", targets: ["InboxFeature"]),
    ],
    dependencies: [
        .package(path: "../../Mail/MailSync"),
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Core/DesignSystem"),
    ],
    targets: [
        .target(
            name: "InboxFeature",
            dependencies: [
                "MailSync",
                "AIKit",
                "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "InboxFeatureTests", dependencies: ["InboxFeature"]),
    ]
)
