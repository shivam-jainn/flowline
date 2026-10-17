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
            dependencies: ["StepItIR", "StepItPipeline"],
            path: "Sources/StepItCaptureAPI"
        ),
        .target(
            name: "StepItEngine",
            dependencies: ["StepItIR", "StepItPipeline", "StepItCaptureAPI", "StepItStorage", "StepItAIGateway", "StepItPublishing"],
            path: "Sources/StepItEngine"
        ),
        .target(
            name: "StepItStorage",
            dependencies: ["StepItIR"],
            path: "Sources/StepItStorage"
        ),
        .target(
            name: "StepItMacCapture",
            dependencies: ["StepItIR", "StepItCaptureAPI", "StepItPipeline", "StepItStorage"],
            path: "Sources/StepItMacCapture"
        ),
        .target(
            name: "StepItPublishing",
            dependencies: ["StepItIR", "StepItStorage"],
            path: "Sources/StepItPublishing"
        ),
        .target(
            name: "StepItAIGateway",
            dependencies: ["StepItIR", "StepItStorage"],
            path: "Sources/StepItAIGateway"
        ),
        .target(
            name: "StepItPermissions",
            dependencies: ["StepItIR"],
            path: "Sources/StepItPermissions"
        ),
        .target(
            name: "StepItFixtures",
            dependencies: coreModules,
            path: "Sources/StepItFixtures"
        ),
        // R/M2-07: UniFFI-generated Swift bindings over the Rust core.
        // Rebuilt by Scripts/build-rust-ffi.sh (binary artifact gitignored).
        .binaryTarget(
            name: "stepit_ffiFFI",
            path: "Generated/stepit_ffiFFI.xcframework"
        ),
        .target(
            name: "StepItFFI",
            dependencies: ["stepit_ffiFFI"],
            path: "Generated/StepItFFI"
        ),
        .executableTarget(
            name: "StepIt",
            dependencies: ["StepItFixtures"] + coreModules,
            path: "Sources/StepIt"
        ),
        .testTarget(
            name: "StepItTests",
            dependencies: ["StepItFixtures", "StepItFFI"] + coreModules,
            path: "Tests/StepItTests"
        )
    ]
)
