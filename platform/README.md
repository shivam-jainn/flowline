# platform/ — per-OS homes

Each OS gets one directory. Cross-platform logic never lives here; it lives
in `core/` (Rust) or `shared/` (contracts/fixtures/goldens).

- `macos/` — the macOS SwiftPM package: the app, all Swift modules, and all
  macOS-only code (ScreenCaptureKit/AX/Vision drivers, SwiftUI/AppKit surfaces).
- `windows/` — roadmap home for the Windows surface. The capture core already
  exists: `core/crates/flowline_win_capture` (+ `x86_64-pc-windows-msvc` gate).
