// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFoundation",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppFoundation", targets: ["AppFoundation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "AppFoundation",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AppFoundationTests", dependencies: ["AppFoundation"]),
    ]
)
