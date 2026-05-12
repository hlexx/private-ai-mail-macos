// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIEvals",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIEvals", targets: ["AIEvals"]),
    ],
    dependencies: [
        .package(path: "../AIKit"),
    ],
    targets: [
        .target(
            name: "AIEvals",
            dependencies: [
                "AIKit",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIEvalsTests", dependencies: ["AIEvals"]),
    ]
)
