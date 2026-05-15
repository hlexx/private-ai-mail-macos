// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIEvals",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIEvals", targets: ["AIEvals"]),
        .executable(name: "EvalRunnerCLI", targets: ["EvalRunnerCLI"]),
    ],
    dependencies: [
        .package(path: "../AIKit"),
        .package(path: "../AIRuntime"),
    ],
    targets: [
        .target(
            name: "AIEvals",
            dependencies: [
                "AIKit",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "EvalRunnerCLI",
            dependencies: ["AIEvals", "AIKit", "AIRuntime"]
        ),
        .testTarget(name: "AIEvalsTests", dependencies: ["AIEvals", "AIKit"]),
    ]
)
