// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Punchcard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Punchcard", targets: ["Punchcard"]),
    ],
    targets: [
        .target(name: "PunchcardCore"),
        .executableTarget(
            name: "Punchcard",
            dependencies: ["PunchcardCore"]
        ),
        .testTarget(
            name: "PunchcardCoreTests",
            dependencies: ["PunchcardCore"]
        ),
    ]
)
