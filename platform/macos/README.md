# platform/macos — the macOS app (SwiftPM package)

All Swift in the monolith lives here. One package, twelve targets.

```
platform/macos/
  Package.swift   Manifest. Paths are package-relative (Sources/, Tests/,
                  Generated/ all sit beside it). Binary target
                  flowline_ffiFFI → Generated/flowline_ffiFFI.xcframework;
                  FlowlineFFI → Generated/FlowlineFFI/ (both rebuilt by `make ffi`).
  Sources/
    Flowline/            App (App/) + CLI (CLI/) + UI (UI/) + main.swift
    FlowlineIR/          Session / event / manifest types (Foundation-only)
    FlowlinePipeline/    Debounce / classify / aggregate / redact / step factory
    FlowlineCaptureAPI/  Driver SPI + registry (Foundation-only)
    FlowlineEngine/      RecorderWorkflowEngine + reducer / gates / enrichment
    FlowlineStorage/     SessionStore + filesystem gateway
    FlowlineMacCapture/  macOS drivers (AppKit/ScreenCaptureKit live here only)
    FlowlinePublishing/  Markdown / web-doc / PDF exporters (WebKit/PDFKit confined here)
    FlowlineAIGateway/   Multi-provider AI gateway
    FlowlinePermissions/ Permissions protocol + macOS impl
    FlowlineFixtures/    Fixture-driven demo tooling (resolves shared/fixtures/)
  Tests/FlowlineTests/   Unit + integration tests (DataLine/ = PhaseNN*.swift)
  Generated/           UniFFI/XCFramework outputs — gitignored, `make ffi` rebuilds
  Assets/              AppIcon + DMG artwork (used by tooling/release/)
```

Build from the repo root (`make build`), never bare `swift build` here on a
clean checkout — the FFI artifacts must exist first.
