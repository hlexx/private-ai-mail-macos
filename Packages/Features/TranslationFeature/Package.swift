// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslationFeature",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TranslationFeature", targets: ["TranslationFeature"]),
    ],
    dependencies: [
        .package(path: "../../Core/DesignSystem"),
        .package(path: "../../Core/Persistence"),
    ],
    targets: [
        .target(
            name: "TranslationFeature",
            dependencies: [
                "DesignSystem",
                "Persistence",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TranslationFeatureTests", dependencies: ["TranslationFeature"]),
    ]
)
