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
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
    ],
    targets: [
        .target(
            name: "AIEmbeddings",
            dependencies: [
                "AppFoundation",
                .product(name: "MLX", package: "mlx-swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIEmbeddingsTests", dependencies: ["AIEmbeddings"]),
    ]
)
