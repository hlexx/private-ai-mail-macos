// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AuthKit", targets: ["AuthKit"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "AuthKit",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AuthKitTests", dependencies: ["AuthKit"]),
    ]
)
