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
        .package(path: "../../AI/AIEmbeddings"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "AttachmentRAG",
            dependencies: [
                "AttachmentKit",
                "AIEmbeddings",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AttachmentRAGTests", dependencies: ["AttachmentRAG"]),
    ]
)
