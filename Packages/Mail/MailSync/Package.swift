// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailSync",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MailSync", targets: ["MailSync"]),
    ],
    dependencies: [
        .package(path: "../MailProviders"),
        .package(path: "../MailIndex"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "MailSync",
            dependencies: [
                "MailProviders",
                "MailIndex",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MailSyncTests", dependencies: ["MailSync"]),
    ]
)
