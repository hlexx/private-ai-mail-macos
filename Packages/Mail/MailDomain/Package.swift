// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailDomain",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MailDomain", targets: ["MailDomain"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "MailDomain",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MailDomainTests", dependencies: ["MailDomain"]),
    ]
)
