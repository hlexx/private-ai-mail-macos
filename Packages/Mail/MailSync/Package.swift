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
        .package(path: "../MailDomain"),
        .package(path: "../MailIndex"),
        .package(path: "../../Core/AppFoundation"),
        .package(path: "../../Core/Persistence"),
        .package(path: "../../Auth/AuthKit"),
    ],
    targets: [
        .target(
            name: "MailSync",
            dependencies: [
                "MailProviders",
                "MailDomain",
                "MailIndex",
                "AppFoundation",
                "Persistence",
                "AuthKit",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MailSyncTests", dependencies: ["MailSync", "AuthKit"]),
    ]
)
