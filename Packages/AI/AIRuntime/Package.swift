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
    ],
    targets: [
        .target(
            name: "AIRuntime",
            dependencies: [
                "AppFoundation",
                "AIPrompts",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIRuntimeTests", dependencies: ["AIRuntime"]),
    ]
)
