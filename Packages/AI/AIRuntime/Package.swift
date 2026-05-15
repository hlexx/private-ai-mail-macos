// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIRuntime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIRuntime", targets: ["AIRuntime"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
        .package(path: "../AIPrompts"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.12"),
    ],
    targets: [
        .target(
            name: "AIRuntime",
            dependencies: [
                "AppFoundation",
                "AIPrompts",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIRuntimeTests", dependencies: ["AIRuntime"]),
    ]
)
