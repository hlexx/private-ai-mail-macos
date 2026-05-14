// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIPrompts",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIPrompts", targets: ["AIPrompts"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "AIPrompts",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AIPromptsTests",
            dependencies: ["AIPrompts"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
