// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailIndex",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MailIndex", targets: ["MailIndex"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
        .package(path: "../../Core/Persistence"),
        .package(path: "../MailDomain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MailIndex",
            dependencies: [
                "AppFoundation",
                "Persistence",
                "MailDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MailIndexTests",
            dependencies: [
                "MailIndex",
                "AppFoundation",
                "Persistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
