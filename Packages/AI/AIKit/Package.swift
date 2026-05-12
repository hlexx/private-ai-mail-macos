// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIKit", targets: ["AIKit"]),
    ],
    dependencies: [
        .package(path: "../AIRuntime"),
        .package(path: "../AIEmbeddings"),
        .package(path: "../../Mail/MailDomain"),
    ],
    targets: [
        .target(
            name: "AIKit",
            dependencies: [
                "AIRuntime",
                "AIEmbeddings",
                "MailDomain",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AIKitTests", dependencies: ["AIKit"]),
    ]
)
