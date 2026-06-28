// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CraftMeter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CraftMeterApp", targets: ["CraftMeterApp"]),
        .executable(name: "meter", targets: ["meter"]),
        .library(name: "CraftMeterCore", targets: ["CraftMeterCore"]),
    ],
    targets: [
        .target(
            name: "CraftMeterCore",
            path: "Sources/CraftMeterCore",
            exclude: ["CLAUDE.md"]
        ),
        .executableTarget(
            name: "CraftMeterApp",
            dependencies: ["CraftMeterCore"],
            path: "Sources/CraftMeterApp",
            exclude: ["CLAUDE.md"]
        ),
        .executableTarget(
            name: "meter",
            dependencies: ["CraftMeterCore"],
            path: "Sources/meter",
            exclude: ["CLAUDE.md"]
        ),
        .testTarget(
            name: "CraftMeterCoreTests",
            dependencies: ["CraftMeterCore"],
            path: "Tests/CraftMeterCoreTests"
        ),
    ]
)
