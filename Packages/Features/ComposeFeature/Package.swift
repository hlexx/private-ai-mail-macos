// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ComposeFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComposeFeature", targets: ["ComposeFeature"]),
    ],
    dependencies: [
        .package(path: "../../Mail/MailProviders"),
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Core/DesignSystem"),
    ],
    targets: [
        .target(
            name: "ComposeFeature",
            dependencies: [
                "MailProviders",
                "AIKit",
                "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ComposeFeatureTests", dependencies: ["ComposeFeature"]),
    ]
)
