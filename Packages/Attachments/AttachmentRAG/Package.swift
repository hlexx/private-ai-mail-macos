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
    ],
    targets: [
        .target(
            name: "AttachmentRAG",
            dependencies: [
                "AttachmentKit",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AttachmentRAGTests", dependencies: ["AttachmentRAG"]),
    ]
)
