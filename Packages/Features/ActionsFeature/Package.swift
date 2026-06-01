// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActionsFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ActionsFeature", targets: ["ActionsFeature"]),
    ],
    dependencies: [
        .package(path: "../../Integrations/IntegrationBroker"),
        .package(path: "../../Integrations/IntegrationDomain"),
        .package(path: "../../AI/AIKit"),
        .package(path: "../../Core/DesignSystem"),
    ],
    targets: [
        .target(
            name: "ActionsFeature",
            dependencies: [
                "IntegrationBroker",
                "IntegrationDomain",
                "AIKit",
                "DesignSystem",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ActionsFeatureTests", dependencies: ["ActionsFeature"]),
    ]
)
