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
        .package(path: "../../Core/DesignSystem"),
    ],
    targets: [
        .target(
            name: "BriefFeature",
            dependencies: [
                "AIKit",
                "MailDomain",
                "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BriefFeatureTests", dependencies: ["BriefFeature"]),
    ]
)
