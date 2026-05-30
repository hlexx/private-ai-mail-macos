// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InboxFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InboxFeature", targets: ["InboxFeature"]),
    ],
    dependencies: [
        .package(path: "../../Mail/MailIndex"),
        .package(path: "../../Mail/MailSync"),
        .package(path: "../../Mail/MailDomain"),
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Core/DesignSystem"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "InboxFeature",
            dependencies: [
                "MailIndex",
                "MailSync",
                "MailDomain",
                "AIKit",
                "DesignSystem",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "InboxFeatureTests", dependencies: ["InboxFeature", "MailIndex", "MailDomain", "Persistence"]),
    ]
)
