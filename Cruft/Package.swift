// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Cruft",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CruftCore", targets: ["CruftCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.10.0")),
    ],
    targets: [
        .target(
            name: "CruftCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "CruftCoreTests",
            dependencies: [
                "CruftCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
