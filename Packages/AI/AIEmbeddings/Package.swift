// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIEmbeddings",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIEmbeddings", targets: ["AIEmbeddings"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "AIEmbeddings",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIEmbeddingsTests", dependencies: ["AIEmbeddings"]),
    ]
)
