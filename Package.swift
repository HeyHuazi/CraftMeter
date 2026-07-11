// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CraftMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CraftMeter",
            targets: ["OhMyUsage"]
        )
    ],
    targets: [
        .target(
            name: "OhMyUsageDomain"
        ),
        .target(
            name: "OhMyUsageInfrastructure",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageProviders",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageApplication",
            dependencies: ["OhMyUsageDomain"],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsagePresentation",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageFeatures",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageApplication",
                "OhMyUsagePresentation"
            ]
        ),
        .target(
            name: "OhMyUsageBootstrap",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageApplication",
                "OhMyUsageFeatures",
                "OhMyUsagePresentation"
            ]
        ),
        .executableTarget(
            name: "OhMyUsage",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders",
                "OhMyUsageApplication",
                "OhMyUsagePresentation",
                "OhMyUsageFeatures",
                "OhMyUsageBootstrap"
            ],
            exclude: ["App/CLAUDE.md", "Services/CLAUDE.md"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OhMyUsageTests",
            dependencies: [
                "OhMyUsage",
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders",
                "OhMyUsageApplication",
                "OhMyUsagePresentation",
                "OhMyUsageFeatures",
                "OhMyUsageBootstrap"
            ],
            exclude: [
                "Fixtures"
            ]
        )
    ]
)
