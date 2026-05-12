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
    ],
    targets: [
        .target(
            name: "AIRuntime",
            dependencies: [
                "AppFoundation",
                "AIPrompts",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIRuntimeTests", dependencies: ["AIRuntime"]),
    ]
)
