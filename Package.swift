// swift-tools-version: 5.9
import PackageDescription

let coreModules: [Target.Dependency] = [
    "StepItIR",
    "StepItPipeline",
    "StepItEngine",
    "StepItStorage",
    "StepItCaptureAPI",
    "StepItMacCapture",
    "StepItPublishing",
    "StepItAIGateway",
    "StepItPermissions",
]

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
            name: "StepItIR",
            dependencies: [],
            path: "Sources/StepItIR"
        ),
        .target(
            name: "StepItPipeline",
            dependencies: ["StepItIR"],
            path: "Sources/StepItPipeline"
        ),
        .target(
            name: "StepItCaptureAPI",
            dependencies: ["StepItIR"],
            path: "Sources/StepItCaptureAPI"
        ),
        .target(
            name: "StepItEngine",
            dependencies: ["StepItIR", "StepItPipeline", "StepItCaptureAPI", "StepItStorage"],
            path: "Sources/StepItEngine"
        ),
        .target(
            name: "StepItStorage",
            dependencies: ["StepItIR"],
            path: "Sources/StepItStorage"
        ),
        .target(
            name: "StepItMacCapture",
            dependencies: ["StepItIR", "StepItCaptureAPI", "StepItPipeline"],
            path: "Sources/StepItMacCapture"
        ),
        .target(
            name: "StepItPublishing",
            dependencies: ["StepItIR", "StepItStorage"],
            path: "Sources/StepItPublishing"
        ),
        .target(
            name: "StepItAIGateway",
            dependencies: ["StepItIR"],
            path: "Sources/StepItAIGateway"
        ),
        .target(
            name: "StepItPermissions",
            dependencies: ["StepItIR"],
            path: "Sources/StepItPermissions"
        ),
        .target(
            name: "StepItCore",
            dependencies: coreModules,
            path: "Sources/StepItCore"
        ),
        .target(
            name: "StepItFixtures",
            dependencies: ["StepItCore"] + coreModules,
            path: "Sources/StepItFixtures"
        ),
        .executableTarget(
            name: "StepIt",
            dependencies: ["StepItCore", "StepItFixtures"] + coreModules,
            path: "Sources/StepIt"
        ),
        .testTarget(
            name: "StepItTests",
            dependencies: ["StepItCore", "StepItFixtures"] + coreModules,
            path: "Tests/StepItTests"
        )
    ]
)
