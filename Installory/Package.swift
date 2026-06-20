// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Installory",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InstalloryCore", targets: ["InstalloryCore"]),
    ],
    dependencies: [
        // Pinned to the minor series so a clean checkout years from now resolves
        // to a known-good GRDB 7.10.x rather than drifting to a future 7.x minor.
        // Commit Package.resolved alongside this for a fully reproducible build.
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.10.0")),
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
