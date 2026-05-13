// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThreadFeature", targets: ["ThreadFeature"]),
    ],
    dependencies: [
        .package(path: "../../Mail/MailSync"),
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Attachments/AttachmentKit"),
        .package(path: "../../Core/DesignSystem"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "ThreadFeature",
            dependencies: [
                "MailSync",
                "AIKit",
                "AttachmentKit",
                "DesignSystem",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ThreadFeatureTests", dependencies: ["ThreadFeature"]),
    ]
)
