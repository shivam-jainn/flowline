# platform/macos — macOS implementation

Everything macOS-specific, all Swift, lives in `apps/desktop/`:

- App + CLI entry points: `apps/desktop/Sources/StepIt/`
- macOS drivers (ScreenCaptureKit, AX, Vision, event taps): `apps/desktop/Sources/StepItMacCapture/`
- Review/UI surfaces (SwiftUI/AppKit): `apps/desktop/Sources/StepIt/UI/`
- App assets (icon, DMG art): `apps/desktop/Assets/`

Portable modules (`StepItIR`, `StepItPipeline`, `StepItEngine`, `StepItStorage`,
`StepItCaptureAPI`) are OS-neutral by gate rule and stay importable anywhere.
