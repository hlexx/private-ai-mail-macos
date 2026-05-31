// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BriefFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BriefFeature", targets: ["BriefFeature"]),
    ],
    dependencies: [
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Mail/MailDomain"),
        .package(path: "../../Core/AppFoundation"),
        .package(path: "../../Core/DesignSystem"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "BriefFeature",
            dependencies: [
                "AIKit",
                "MailDomain",
                "AppFoundation",
                "DesignSystem",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BriefFeatureTests", dependencies: ["BriefFeature", "AIKit", "Persistence"]),
    ]
)
