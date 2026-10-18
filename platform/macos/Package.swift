// swift-tools-version: 5.9
import PackageDescription

let coreModules: [Target.Dependency] = [
    "FlowlineIR",
    "FlowlinePipeline",
    "FlowlineEngine",
    "FlowlineStorage",
    "FlowlineCaptureAPI",
    "FlowlineMacCapture",
    "FlowlinePublishing",
    "FlowlineAIGateway",
    "FlowlinePermissions",
    "FlowlineTemplates",
]

let package = Package(
    name: "Flowline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "flowline", targets: ["Flowline"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FlowlineIR",
            dependencies: [],
            path: "Sources/FlowlineIR"
        ),
        .target(
            name: "FlowlinePipeline",
            dependencies: ["FlowlineIR", "FlowlineFFI"],
            path: "Sources/FlowlinePipeline"
        ),
        .target(
            name: "FlowlineCaptureAPI",
            dependencies: ["FlowlineIR", "FlowlinePipeline"],
            path: "Sources/FlowlineCaptureAPI"
        ),
        .target(
            name: "FlowlineEngine",
            dependencies: ["FlowlineIR", "FlowlinePipeline", "FlowlineCaptureAPI", "FlowlineStorage", "FlowlineAIGateway", "FlowlinePublishing"],
            path: "Sources/FlowlineEngine"
        ),
        .target(
            name: "FlowlineStorage",
            dependencies: ["FlowlineIR"],
            path: "Sources/FlowlineStorage"
        ),
        .target(
            name: "FlowlineMacCapture",
            dependencies: ["FlowlineIR", "FlowlineCaptureAPI", "FlowlinePipeline", "FlowlineStorage"],
            path: "Sources/FlowlineMacCapture"
        ),
        .target(
            name: "FlowlinePublishing",
            dependencies: ["FlowlineIR", "FlowlineStorage"],
            path: "Sources/FlowlinePublishing"
        ),
        .target(
            name: "FlowlineAIGateway",
            dependencies: ["FlowlineIR", "FlowlineStorage"],
            path: "Sources/FlowlineAIGateway"
        ),
        .target(
            name: "FlowlinePermissions",
            dependencies: ["FlowlineIR"],
            path: "Sources/FlowlinePermissions"
        ),
        .target(
            name: "FlowlineTemplates",
            dependencies: ["FlowlineIR"],
            path: "Sources/FlowlineTemplates"
        ),
        .target(
            name: "FlowlineFixtures",
            dependencies: coreModules,
            path: "Sources/FlowlineFixtures"
        ),
        // R/M2-07: UniFFI-generated Swift bindings over the Rust core.
        // Rebuilt by Scripts/build-rust-ffi.sh (binary artifact gitignored).
        .binaryTarget(
            name: "flowline_ffiFFI",
            path: "Generated/flowline_ffiFFI.xcframework"
        ),
        .target(
            name: "FlowlineFFI",
            dependencies: ["flowline_ffiFFI"],
            path: "Generated/FlowlineFFI"
        ),
        .executableTarget(
            name: "Flowline",
            dependencies: ["FlowlineFixtures"] + coreModules,
            path: "Sources/Flowline",
            exclude: [
                "UI/Flowline/Diagnostics/INSTRUMENTS_GUTTER.md",
                "UI/Flowline/Diagnostics/PROVIDER_NOTES.md",
            ]
        ),
        .testTarget(
            name: "FlowlineTests",
            dependencies: ["FlowlineFixtures", "FlowlineFFI"] + coreModules,
            path: "Tests/FlowlineTests"
        )
    ]
)
