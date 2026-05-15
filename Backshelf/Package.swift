// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Backshelf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BackshelfCore", targets: ["BackshelfCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.10.0")),
    ],
    targets: [
        .target(
            name: "BackshelfCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "BackshelfCoreTests",
            dependencies: [
                "BackshelfCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
