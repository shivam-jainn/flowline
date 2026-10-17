# platform/macos — the macOS app (SwiftPM package)

All Swift in the monolith lives here. One package, twelve targets.

```
platform/macos/
  Package.swift   Manifest. Paths are package-relative (Sources/, Tests/,
                  Generated/ all sit beside it). Binary target
                  stepit_ffiFFI → Generated/stepit_ffiFFI.xcframework;
                  StepItFFI → Generated/StepItFFI/ (both rebuilt by `make ffi`).
  Sources/
    StepIt/            App (App/) + CLI (CLI/) + UI (UI/) + main.swift
    StepItIR/          Session / event / manifest types (Foundation-only)
    StepItPipeline/    Debounce / classify / aggregate / redact / step factory
    StepItCaptureAPI/  Driver SPI + registry (Foundation-only)
    StepItEngine/      RecorderWorkflowEngine + reducer / gates / enrichment
    StepItStorage/     SessionStore + filesystem gateway
    StepItMacCapture/  macOS drivers (AppKit/ScreenCaptureKit live here only)
    StepItPublishing/  Markdown / web-doc / PDF exporters (WebKit/PDFKit confined here)
    StepItAIGateway/   Multi-provider AI gateway
    StepItPermissions/ Permissions protocol + macOS impl
    StepItFixtures/    Fixture-driven demo tooling (resolves shared/fixtures/)
  Tests/StepItTests/   Unit + integration tests (DataLine/ = PhaseNN*.swift)
  Generated/           UniFFI/XCFramework outputs — gitignored, `make ffi` rebuilds
  Assets/              AppIcon + DMG artwork (used by tooling/release/)
```

Build from the repo root (`make build`), never bare `swift build` here on a
clean checkout — the FFI artifacts must exist first.
