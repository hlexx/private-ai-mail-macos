// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailIndex",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MailIndex", targets: ["MailIndex"]),
    ],
    dependencies: [
        .package(path: "../../Core/Persistence"),
        .package(path: "../MailDomain"),
    ],
    targets: [
        .target(
            name: "MailIndex",
            dependencies: [
                "Persistence",
                "MailDomain",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MailIndexTests", dependencies: ["MailIndex"]),
    ]
)
