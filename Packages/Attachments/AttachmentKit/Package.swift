// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AttachmentKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AttachmentKit", targets: ["AttachmentKit"]),
    ],
    dependencies: [
        .package(path: "../../Core/AppFoundation"),
    ],
    targets: [
        .target(
            name: "AttachmentKit",
            dependencies: [
                "AppFoundation",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AttachmentKitTests", dependencies: ["AttachmentKit"]),
    ]
)
