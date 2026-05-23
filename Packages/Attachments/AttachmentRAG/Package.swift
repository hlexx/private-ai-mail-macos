// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AttachmentRAG",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AttachmentRAG", targets: ["AttachmentRAG"]),
    ],
    dependencies: [
        .package(path: "../AttachmentKit"),
        .package(path: "../../Core/Persistence"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "AttachmentRAG",
            dependencies: [
                "AttachmentKit",
                "Persistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AttachmentRAGTests",
            dependencies: [
                "AttachmentRAG",
                "Persistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
