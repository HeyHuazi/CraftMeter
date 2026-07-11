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
            name: "OhMyUsageDomain",
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsageInfrastructure",
            dependencies: ["OhMyUsageDomain"],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsageProviders",
            dependencies: ["OhMyUsageDomain"],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsageApplication",
            dependencies: ["OhMyUsageDomain"],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsagePresentation",
            dependencies: ["OhMyUsageDomain"],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsageFeatures",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageApplication",
                "OhMyUsagePresentation"
            ],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "OhMyUsageBootstrap",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageApplication",
                "OhMyUsageFeatures",
                "OhMyUsagePresentation"
            ],
            exclude: ["CLAUDE.md"]
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
            exclude: [
                "CLAUDE.md",
                "App/CLAUDE.md",
                "Models/CLAUDE.md",
                "Services/CLAUDE.md",
                "UI/Settings/CLAUDE.md"
            ],
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
