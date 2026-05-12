// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntegrationBroker",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IntegrationBroker", targets: ["IntegrationBroker"]),
    ],
    dependencies: [
        .package(path: "../IntegrationDomain"),
        .package(path: "../../Auth/AuthKit"),
    ],
    targets: [
        .target(
            name: "IntegrationBroker",
            dependencies: [
                "IntegrationDomain",
                "AuthKit",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "IntegrationBrokerTests", dependencies: ["IntegrationBroker"]),
    ]
)
