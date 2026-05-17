// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Installory",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "InstalloryCore", targets: ["InstalloryCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.10.0")),
    ],
    targets: [
        .target(
            name: "InstalloryCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "InstalloryCoreTests",
            dependencies: [
                "InstalloryCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
