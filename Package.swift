// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Punchcard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Punchcard", targets: ["Punchcard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "PunchcardCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources/Migrations")]
        ),
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
