// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StepIt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "stepit", targets: ["StepIt"]),
        .library(name: "StepItCore", targets: ["StepItCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StepItCore",
            dependencies: [],
            path: "Sources/StepItCore"
        ),
        .target(
            name: "StepItFixtures",
            dependencies: ["StepItCore"],
            path: "Sources/StepItFixtures"
        ),
        .executableTarget(
            name: "StepIt",
            dependencies: ["StepItCore", "StepItFixtures"],
            path: "Sources/StepIt"
        ),
        .testTarget(
            name: "StepItTests",
            dependencies: ["StepItCore", "StepItFixtures"],
            path: "Tests/StepItTests"
        )
    ]
)
