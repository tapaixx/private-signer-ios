// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PrivateSigner",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "PrivateSignerKit", targets: ["PrivateSignerKit"]),
        .library(name: "PrivateSignerSelfUpdate", targets: ["PrivateSignerSelfUpdate"]),
        .library(name: "PrivateSignerUI", targets: ["PrivateSignerUI"]),
    ],
    targets: [
        .target(
            name: "PrivateSignerKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "PrivateSignerSelfUpdate",
            dependencies: ["PrivateSignerKit"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "PrivateSignerUI",
            dependencies: ["PrivateSignerKit", "PrivateSignerSelfUpdate"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PrivateSignerKitTests",
            dependencies: ["PrivateSignerKit"]
        ),
        .testTarget(
            name: "PrivateSignerSelfUpdateTests",
            dependencies: ["PrivateSignerSelfUpdate"]
        ),
    ]
)
