// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailProviders",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MailProviders", targets: ["MailProviders"]),
    ],
    dependencies: [
        .package(path: "../MailDomain"),
        .package(path: "../../Core/AppFoundation"),
        .package(path: "../../Auth/AuthKit"),
    ],
    targets: [
        .target(
            name: "MailProviders",
            dependencies: [
                "MailDomain",
                "AppFoundation",
                "AuthKit",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MailProvidersTests",
            dependencies: ["MailProviders"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
