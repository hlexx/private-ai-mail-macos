// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntegrationDomain",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IntegrationDomain", targets: ["IntegrationDomain"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "IntegrationDomain",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "IntegrationDomainTests", dependencies: ["IntegrationDomain"]),
    ]
)
