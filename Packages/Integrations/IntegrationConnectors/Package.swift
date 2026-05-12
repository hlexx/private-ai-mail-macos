// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntegrationConnectors",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IntegrationConnectors", targets: ["IntegrationConnectors"]),
    ],
    dependencies: [
        .package(path: "../IntegrationDomain"),
    ],
    targets: [
        .target(
            name: "IntegrationConnectors",
            dependencies: [
                "IntegrationDomain",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "IntegrationConnectorsTests", dependencies: ["IntegrationConnectors"]),
    ]
)
